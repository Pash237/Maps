//
//  MapScrollView.swift
//  maps
//
//  Created by Pavel Alexeev on 02.06.2022.
//

import UIKit

public class MapScrollView: UIView {
	public var offset: Point = .zero
	public var zoom: Double = 11
	public var rotation: Radians = 0.0
	
	public var contentInset: UIEdgeInsets = .zero {
		didSet {
			guard contentInset != oldValue else { return }
			
			let oldCenter = camera.center
			camera = currentCamera()
			let newCenter = camera.center
			
			// avoid unwanted animation change when contentInset changes during animation
			targetCamera = targetCamera.with(center: targetCamera.center + newCenter - oldCenter)
		}
	}
	
	public var singleTapGestureEnabled = true
	public var longPressGestureEnabled = true
	public var dragGestureEnabled = true
	public var rotationGestureEnabled = true
	public var doubleTapZoomGestureEnabled = true
	public var doubleTapDragZoomGestureEnabled = true
	public var pinchZoomGestureEnabled = true
	public var zoomAndRotationAnchor: CGPoint?
	
	private var previousTouchesCount = 0
	private var previousCentroidInWindow: CGPoint?
	private var previousCentroid: CGPoint?
	private var previousDistance: CGFloat?
	private var lastZoomGestureTwoFingerDistance: CGFloat = 300
	
	private var centroidToCalculateVelocity: CGPoint?
	private var timestampToCalculateVelocity: TimeInterval?
	private var velocity: CGPoint = .zero
	public private(set) var targetCamera: Camera
	private var speedToTargetCamera: CGFloat = 0	// 0...1
	
	private var lastTouchTimestamp: TimeInterval = 0
	private var lastTouchLocation: CGPoint = .zero
	private var lastTouchTravelDistance: CGFloat = 0
	private var previousTouchEndCentroid: CGPoint?
	private var previousTouchTravelDistance: CGFloat = 0
	private var doubleTapDragZooming = false
	private var doubleTapDragZoomCenter: CGPoint = .zero
	private let doubleTapDragZoomDelay: TimeInterval = 0.26
	private let longPressDuration: TimeInterval = 0.26
	private let doubleTapDragZoomSpeed = 0.012
	private let tapHoldDuration = 0.25
	private var twoFingerTapTimestamp: TimeInterval?
	private var twoFingerTravelDistance: CGFloat = 0
	private var doubleTapZoomTimestamp: TimeInterval?
	private var lastTouchEndedEventTimestamp: TimeInterval = 0
	
	private var singleTapPossible = false
	private var longPressWorkItem: DispatchWorkItem?
	private var isLongPressing = false
	private var trackingLayer: AnyHashable?
	private var draggingLayer: AnyHashable?
	private var draggingPoint: CGPoint = .zero
	
	private let initialRotationGestureThreshold: Radians = 0.25
	private var rotationGestureThreshold: Radians = 0.25
	private var rotationGestureDetected = false
	private var lastRotationTimestamp: TimeInterval = 0
	private var touchesBeganAngle: Radians?
	private var touchesBeganDistance: Double?
	private var previousAngle: Radians?
	
	private var touchesBeganTimestamps: [Int: TimeInterval] = [:]
	
	public var projection = SphericalMercator()
	
	public private(set) var camera: Camera
	
	private lazy var animationDisplayLink: CADisplayLink = {
		let displayLink = CADisplayLink(target: self, selector: #selector(onDisplayLink(_:)))
		displayLink.add(to: .current, forMode: .common)
		if #available(iOS 15.0, *) {
			displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
		}
		displayLink.isPaused = true
		return displayLink
	}()
	
	init(frame: CGRect, camera: Camera) {
		print("init map with \(camera)")
		
		self.targetCamera = camera
		self.camera = camera
		super.init(frame: frame)
		
		isMultipleTouchEnabled = true
		backgroundColor = .black
		
		updateOffset(to: camera, reason: .initialize)
	}
	
	
	private var oldOffset: Point = .zero
	private var oldZoom: Double = 0
	private var oldRotation: Radians = -10000
	private var scrollChange: ScrollChange = .zero
	private var scrollReason: ScrollReason = .other
	
	func updateOffset(to camera: Camera, reason: ScrollReason) {
		self.camera = camera
		zoom = camera.zoom
		offset = point(at: camera.center) - contentBounds.center
		rotation = camera.rotation.inRange
		
		if oldZoom != zoom || oldRotation != rotation || oldOffset.distance(to: offset) > 0.2 {
			didScroll(reason: reason, change: scrollChange)
		} else {
			// movement is too small — do not fire didScroll event
		}
	}
	
	func didScroll(reason: ScrollReason, change: ScrollChange) {
		oldOffset = offset
		oldZoom = zoom
		oldRotation = rotation
	}
	
	public func setCamera(_ newCamera: Camera, animated: Bool = true, reason: ScrollReason? = nil) {
		let targetCamera = newCamera.withRotationClose(to: camera.rotation)
		var animated = animated
		scrollReason = reason ?? scrollReason
		if animated {
			let midZoom = (targetCamera.zoom + camera.zoom)/2
			let targetPoint = projection.point(at: midZoom, from: targetCamera.center)
			let currentPoint = projection.point(at: midZoom, from: camera.center)
			let tooFar = (targetPoint - currentPoint).maxDimension > max(bounds.width, bounds.height) * 3
			if tooFar {
				animated = false
			}
		}
		
		guard animated else {
			self.targetCamera = targetCamera
			updateOffset(to: targetCamera, reason: scrollReason)
			return
		}
		
		self.targetCamera = targetCamera
		if speedToTargetCamera != 1 {
			speedToTargetCamera = min(speedToTargetCamera, 0.3)	// hacky solution, but good enough
		}
		animationDisplayLink.isPaused = false
	}
	
	private func currentCamera() -> Camera {
		Camera(center: coordinates(at: contentBounds.center), zoom: zoom, rotation: rotation)
	}
	
	public func coordinates(at screenPoint: CGPoint) -> Coordinates {
		projection.coordinates(from: offset + screenPoint, at: zoom)
	}
	
	public func point(at coordinates: Coordinates) -> Point {
		projection.point(at: zoom, from: coordinates)
	}
	public func screenPoint(at coordinates: Coordinates) -> Point {
		point(at: coordinates) - offset
	}
	
	public var coordinateBounds: CoordinateBounds {
		CoordinateBounds(northeast: coordinates(at: CGPoint(contentBounds.width, 0)),
						 southwest: coordinates(at: CGPoint(0, contentBounds.height)))
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesBegan(touches, with: event)
		
		guard let event = event else {
			return
		}
		let centroidInWindow = event.centroid()
		let centroid = event.centroid(in: mapContentsView)
		let timeSincePreviousTap = event.timestamp - lastTouchTimestamp
		
		CADisplayLink.enableProMotion()
		
		previousCentroid = centroid
		previousCentroidInWindow = centroidInWindow
		if event.activeTouches.count == 1 {
			previousTouchesCount = event.activeTouches.count
		}
		
		for touch in touches {
			touchesBeganTimestamps[touch.hash] = touch.timestamp
		}
		
		// detect double tap
		if event.activeTouches.count == 1 && lastTouchTravelDistance < 10 && timeSincePreviousTap < doubleTapDragZoomDelay && abs(centroid.x - lastTouchLocation.x) < 30 && abs(centroid.y - lastTouchLocation.y) < 100 && twoFingerTapTimestamp == nil && doubleTapZoomTimestamp == nil && doubleTapDragZoomGestureEnabled {
			doubleTapDragZooming = true
			doubleTapDragZoomCenter = centroid
		} else {
			doubleTapDragZooming = false
			
			longPressWorkItem?.cancel()
			isLongPressing = false
			if event.activeTouches.count == 1 && longPressGestureEnabled {
				longPressWorkItem = DispatchWorkItem(block: {[weak self] in
					guard let self else { return }
					if let trackingLayer, let layerToDrag = shouldStartDragging(trackingLayer, at: centroid) {
						startDragging(layerToDrag, at: centroid)
					} else {
						isLongPressing = true
						onLongPress(point: centroid)
					}
					if let trackingLayer {
						onEndTracking(trackingLayer)
						self.trackingLayer = nil
					}
				})
				DispatchQueue.main.asyncAfter(deadline: .now() + longPressDuration + 0.01, execute: longPressWorkItem!)
			}
		}
		
		if event.activeTouches.count == 2 && (lastTouchTravelDistance < 20 || touches.count == 2) {
			// detect possible two-finger tap
			twoFingerTapTimestamp = event.timestamp
		} else {
			twoFingerTapTimestamp = nil
		}
		
		if event.activeTouches.count >= 2 {
			touchesBeganAngle = event.angle()
			touchesBeganDistance = event.activeTouches[0].location(in: nil).distance(to: event.activeTouches[1].location(in: nil))
			previousAngle = touchesBeganAngle
			endDragging()
		}
		
		camera = currentCamera()
		velocity = .zero
		centroidToCalculateVelocity = centroid
		timestampToCalculateVelocity = event.timestamp
		previousTouchTravelDistance = lastTouchTravelDistance
		lastTouchTravelDistance = 0
		singleTapPossible = false
		scrollReason = .drag
		
		endTracking()
		if event.activeTouches.count == 1,
		   let layer = trackingLayer(at: centroid),
		   singleTapGestureEnabled {
			trackingLayer = layer
			onBeginTracking(layer)
		}
		
		// stop any animation immediately when tapping on the map
		let distanceBetweenLastTwoTouches = (previousTouchEndCentroid ?? .zero).distance(to: previousCentroid ?? .zero)
		if timeSincePreviousTap < doubleTapDragZoomDelay && distanceBetweenLastTwoTouches < 30 {
			// but if we're zooming in with double-tap gesture, we might want to triple-tap,
			// and this zoom animation should resume without stopping
		} else {
			targetCamera = camera
			animationDisplayLink.isPaused = true
		}
	}
	
	public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesMoved(touches, with: event)
		
		guard let event = event,
			  let previousCentroid = previousCentroid,
			  let previousCentroidInWindow = previousCentroidInWindow else {
			return
		}
		
		var allTouches = event.activeTouches
		let centroid = event.centroid(in: mapContentsView)
		let centroidInWindow = event.centroid()
		let previousOffset = offset
		let previousZoom = zoom
		let previousRotation = rotation
		
		CADisplayLink.enableProMotion()
		
		if let draggingLayer, let touch = allTouches.first {
			draggingPoint = touch.location(in: mapContentsView)
			didDragLayer(draggingLayer, to: draggingPoint)
		}
		
		if previousTouchesCount != allTouches.count && ((dragGestureEnabled && draggingLayer == nil) || allTouches.count > 1) {
			offset += centroid - previousCentroid
			
			centroidToCalculateVelocity = centroid
			timestampToCalculateVelocity = event.timestamp
		}
		
		if !doubleTapDragZooming && ((dragGestureEnabled && draggingLayer == nil) || allTouches.count > 1) && !isLongPressing {
			offset += (previousCentroid - centroid)
		}
		
		if zoomAndRotationAnchor != nil, allTouches.count > 1 {
			// don't move
			offset -= (previousCentroid - centroid)
		}
		
		if allTouches.count >= 2 {
			// we might have more that two touches — use first two
			allTouches.sort(by: {
				touchesBeganTimestamps[$0.hash] ?? $0.timestamp > touchesBeganTimestamps[$1.hash] ?? $1.timestamp
			})
			
			let distance = allTouches[0].location(in: nil).distance(to: allTouches[1].location(in: nil))
			let angle = event.angle()!
			
			if let previousDistance,
			   let touchesBeganDistance,
			   pinchZoomGestureEnabled,
			   previousTouchesCount == allTouches.count,
			   abs(previousDistance - distance) < 100 /* deal with sometimes happening touch issues */
			{
				let previousZoom = zoom
				zoom *= 1 + (distance/previousDistance - 1) / zoom*1.5
				
				let zoomCenterOnMap = offset + (zoomAndRotationAnchor ?? centroid)
				let zoomChange = 1.0 - pow(2.0, zoom - previousZoom)
				
				offset -= zoomCenterOnMap * zoomChange
				
				twoFingerTravelDistance += abs(previousDistance - distance)
				rotationGestureThreshold = initialRotationGestureThreshold
				if !rotationGestureDetected {
					// the more we zoom, the less we likely to rotate
					rotationGestureThreshold *= (1.0 + min(twoFingerTravelDistance, 500.0) * 0.003)
					// the closer the fingers, the trickier it is to rotate
					rotationGestureThreshold *= (1.0 + max(260.0 - distance, 0.0) * 0.005)
					// the less we change distance between fingers, the more we likely want to rotate
					rotationGestureThreshold *= (1.0 + min(max(0, abs(distance - touchesBeganDistance) - 20), 200.0) * 0.008)
					
					if event.timestamp - lastRotationTimestamp < 1.2 {
						// easier rotation if we just rotated
						rotationGestureThreshold *= 0.2
					}
				}
				lastZoomGestureTwoFingerDistance = distance
				
				scrollChange.zoom += abs(zoomChange)
			}
			
			if let previousAngle, let touchesBeganAngle, previousTouchesCount == allTouches.count, rotationGestureEnabled {
				if fabs(touchesBeganAngle - angle).inRange > rotationGestureThreshold {
					rotationGestureDetected = true
				}
				if rotationGestureDetected {
					rotation = (rotation + (angle - previousAngle)).inRange
					lastRotationTimestamp = event.timestamp
					
					scrollChange.rotation += abs(angle - previousAngle)
				}
			}
			
			previousDistance = distance
			previousAngle = angle
		}
		
		if let timestamp = timestampToCalculateVelocity, let centroidToCalculateVelocity = centroidToCalculateVelocity {
			let time = event.timestamp - timestamp
			if time > 0.004, event.timestamp - lastTouchEndedEventTimestamp > 0.05 {
				//TODO: use more points to compute velocity
				velocity = (centroid - centroidToCalculateVelocity) / time
			}
		}
		
		if allTouches.count == 1 {
			if doubleTapDragZooming {
				let previousZoom = zoom
				zoom *= 1 + (previousCentroidInWindow - centroidInWindow).y / zoom * doubleTapDragZoomSpeed
				
				let zoomCenterOnMap = offset + (zoomAndRotationAnchor ?? doubleTapDragZoomCenter)
				let zoomChange = 1.0 - pow(2.0, zoom - previousZoom)
				
				offset -= zoomCenterOnMap * zoomChange
			}
			
			if isLongPressing, lastTouchTravelDistance > 30 {
				onMoveLongPress(point: centroid)
			}
			
			lastTouchTravelDistance += (previousCentroid - centroid).length
		}
		
		if !doubleTapDragZooming {
			scrollChange.translation += centroid - previousCentroid
		}
		
		camera = currentCamera()
		targetCamera = camera
		if previousOffset != offset || previousZoom != zoom || previousRotation != rotation {
			didScroll(reason: .drag, change: scrollChange)
		}
		animationDisplayLink.isPaused = true
		
		self.previousCentroid = centroid
		self.previousCentroidInWindow = centroidInWindow
		previousTouchesCount = allTouches.count
		centroidToCalculateVelocity = centroid
		timestampToCalculateVelocity = event.timestamp
		singleTapPossible = false
		longPressWorkItem?.cancel()
		endTracking()
	}
	
	public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesEnded(touches, with: event)
		
		guard let event = event else {
			return
		}
		
		let activeTouches = event.activeTouches
		
		// zoom out animated with two finger tap gesture
		if let twoFingerTapTimestamp = twoFingerTapTimestamp, activeTouches.isEmpty, event.timestamp - twoFingerTapTimestamp < doubleTapDragZoomDelay, twoFingerTravelDistance < 4, doubleTapZoomGestureEnabled {
			let zoomCenterOnMap = offset + (zoomAndRotationAnchor ?? (contentBounds.center + ((previousCentroid ?? contentBounds.center) - contentBounds.center) * 0.5))
			
			setCamera(Camera(center: projection.coordinates(from: zoomCenterOnMap, at: zoom), zoom: zoom - 1, rotation: rotation), animated: true)
		}
		
		let accidentallyMovedOneFingerAfterZoomGesture = event.timestamp - lastTouchEndedEventTimestamp < 0.05 && lastZoomGestureTwoFingerDistance < 90
		
		if activeTouches.count < 2 {
			previousDistance = nil
			previousAngle = nil
			touchesBeganAngle = nil
			rotationGestureDetected = false
			rotationGestureThreshold = initialRotationGestureThreshold
		}
		
		longPressWorkItem?.cancel()
		if isLongPressing, activeTouches.isEmpty {
			onEndLongPress(point: event.centroid())
		}
		isLongPressing = false
		
		if activeTouches.isEmpty && touches.count == 1 {
			let timeSinceTouchBegan = event.timestamp - (touchesBeganTimestamps[touches.first!.hash] ?? 0)
			// zoom in animated with double-tap gesture
			let timeSincePreviousTap = event.timestamp - lastTouchTimestamp
			let distanceBetweenLastTwoTouches = (previousTouchEndCentroid ?? .zero).distance(to: previousCentroid ?? .zero)
			if lastTouchTravelDistance < 30 && previousTouchTravelDistance < 30 && timeSincePreviousTap < doubleTapDragZoomDelay && distanceBetweenLastTwoTouches < 30 && twoFingerTapTimestamp == nil && doubleTapZoomGestureEnabled {
				let zoomCenterOnMap = offset + (zoomAndRotationAnchor ?? (contentBounds.center + ((previousCentroid ?? contentBounds.center) - contentBounds.center) * 0.5))
				doubleTapZoomTimestamp = event.timestamp
				
				setCamera(Camera(center: projection.coordinates(from: zoomCenterOnMap, at: zoom), zoom: zoom + 1, rotation: rotation), animated: true, reason: .drag)
			} else {
				doubleTapZoomTimestamp = nil
			}
			
			if singleTapGestureEnabled && lastTouchTravelDistance == 0 && timeSinceTouchBegan < tapHoldDuration && (timeSincePreviousTap > doubleTapDragZoomDelay || distanceBetweenLastTwoTouches > 30) {
				singleTapPossible = true
				DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapDragZoomDelay + 0.01) {[weak self] in
					guard let self else { return }
					if self.singleTapPossible {
						self.singleTapPossible = false
						endTracking()
						self.onSingleTap(point: self.lastTouchLocation)
					}
				}
			}
			
			if velocity.length < 400 {
				velocity = .zero
			}
			
			if dragGestureEnabled, draggingLayer == nil, doubleTapZoomTimestamp == nil, !doubleTapDragZooming, !accidentallyMovedOneFingerAfterZoomGesture {
				// decelerate drag
				targetCamera = Camera(center: coordinates(at: contentBounds.center - velocity*0.1),
									  zoom: targetCamera.zoom,
									  rotation: targetCamera.rotation)
				if velocity != .zero {
					speedToTargetCamera = 1
					animationDisplayLink.isPaused = false
				} else {
					speedToTargetCamera = 0
				}
			} else if doubleTapDragZooming, lastTouchTravelDistance > 20 {
				// decelerate tap-tap-drag zoom
				let targetZoom = targetCamera.zoom - velocity.y * 0.0005
				let zoomCenterOnMap = offset + (zoomAndRotationAnchor ?? doubleTapDragZoomCenter)
				let zoomChange = 1.0 - pow(2.0, targetZoom - zoom)
				let targetOffset = offset - zoomCenterOnMap * zoomChange
				
				targetCamera = Camera(center: projection.coordinates(from: contentBounds.center + targetOffset, at: targetZoom),
									  zoom: targetZoom,
									  rotation: targetCamera.rotation)
				if velocity != .zero {
					speedToTargetCamera = 1
					animationDisplayLink.isPaused = false
				} else {
					speedToTargetCamera = 0
				}
			}
			
			previousTouchEndCentroid = previousCentroid
			previousCentroid = nil
			doubleTapDragZooming = false
			
			lastTouchTimestamp = event.timestamp
			lastTouchLocation = touches.first!.location(in: mapContentsView)
		} else {
			previousCentroid = activeTouches.centroid(in: mapContentsView)
			speedToTargetCamera = 0
		}
		
		if activeTouches.isEmpty {
			twoFingerTravelDistance = 0
			scrollChange = .zero
			endDragging()
		}
		
		lastTouchEndedEventTimestamp = event.timestamp
		for touch in touches {
			touchesBeganTimestamps.removeValue(forKey: touch.hash)
		}
		
		endTracking()
	}
	
	public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesCancelled(touches, with: event)
		
		guard let allTouches = event?.activeTouches else {
			return
		}
		
		// TODO: stop animations
		
		if allTouches.count < 2 {
			previousDistance = nil
		}
		if allTouches.isEmpty {
			previousCentroid = nil
		}
		for touch in touches {
			touchesBeganTimestamps.removeValue(forKey: touch.hash)
		}
		
		longPressWorkItem?.cancel()
		singleTapPossible = false
		endTracking()
		endDragging()
	}
	
	var mapContentsView: UIView {
		self
	}
	
	private var cameraIsOnTarget: Bool {
		abs(targetCamera.center.latitude - camera.center.latitude) < 0.00001 &&
		abs(targetCamera.center.longitude - camera.center.longitude) < 0.00001 &&
		abs(targetCamera.zoom - camera.zoom) < 0.01 &&
		abs(targetCamera.rotation - camera.rotation) < 0.01
	}
	
	@objc private func onDisplayLink(_ displayLink: CADisplayLink) {
		let actualFrameRate = 1.0 / (displayLink.targetTimestamp - displayLink.timestamp)
		let frameRateAdjustment = 120.0 / actualFrameRate		// think for 120Hz displays for the calculations
		
		let mapScrollSpeed = 0.07
		let acceleration = 1.4 * (1 - speedToTargetCamera) + 1.0 * (speedToTargetCamera)
		speedToTargetCamera = (speedToTargetCamera * acceleration).clamped(to: 0.03...1)
		
		let speed = speedToTargetCamera * mapScrollSpeed * frameRateAdjustment

		var nextCamera = camera
		nextCamera.center += (targetCamera.center - camera.center) * speed
		nextCamera.zoom += (targetCamera.zoom - zoom) * speed
		nextCamera.rotation += (targetCamera.withRotationClose(to: rotation).rotation - rotation) * speed
		
		updateOffset(to: nextCamera, reason: scrollReason)
		
		if camera.isNearlyEqual(to: targetCamera) {
			camera = targetCamera
			speedToTargetCamera = 0
			animationDisplayLink.isPaused = true
		}
	}
	
	func onSingleTap(point: CGPoint) {
		// override if necessary
	}
	
	func onLongPress(point: CGPoint) {
		// override if necessary
	}
	
	func onMoveLongPress(point: CGPoint) {
		// override if necessary
	}
	
	func onEndLongPress(point: CGPoint) {
		// override if necessary
	}
	
	func endTracking() {
		if let trackingLayer, !singleTapPossible {
			onEndTracking(trackingLayer)
			self.trackingLayer = nil
		}
	}
	
	func trackingLayer(at point: CGPoint) -> AnyHashable? {
		nil
	}
	
	func onBeginTracking(_ trackingLayer: AnyHashable) {
		// override if necessary
	}
	
	func onEndTracking(_ trackingLayer: AnyHashable) {
		// override if necessary
	}
	
	func endDragging() {
		if let draggingLayer {
			didEndDraggingLayer(draggingLayer, at: draggingPoint)
			self.draggingLayer = nil
		}
	}
	
	func shouldStartDragging(_ layer: AnyHashable, at point: CGPoint) -> AnyHashable? {
		nil
	}
	
	func didDragLayer(_ layer: AnyHashable, to point: CGPoint) {
		
	}
	
	func didEndDraggingLayer(_ layer: AnyHashable, at point: CGPoint) {
		
	}
	
	public func startDragging(_ layer: AnyHashable, at point: CGPoint?) {
		draggingLayer = layer
		draggingPoint = point ?? previousCentroid ?? .zero
		isLongPressing = false
	}
	
	public var contentBounds: CGRect {
		var contentInset = contentInset
		if contentInset.bottom > bounds.height*0.65 {
			contentInset.bottom = 67
		}
		return bounds.inset(by: contentInset)
	}
}
