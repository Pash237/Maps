//
//  MapScrollView.swift
//  maps
//
//  Created by Pavel Alexeev on 02.06.2022.
//

import UIKit
import Motion

public class MapScrollView: UIView {
	public var offset: Point = .zero
	public var zoom: Double = 11
	public var rotation: Radians = 0.0
	
	public var contentInset: UIEdgeInsets = .zero {
		didSet {
			if oldValue != .zero && contentInset != oldValue {
				// keep map center in the center when content insets changes
				// TODO: animation with frequently changed target does not work correctly with Motion
				// TODO: keep just-touched map region on screen
				// TODO: do not animate when not needed
//				let oldBounds = bounds.inset(by: oldValue)
//				let cameraAtOldCenter = Camera(center: coordinates(at: oldBounds.center), zoom: zoom)
//				setCamera(cameraAtOldCenter, animated: true)
			}
		}
	}
	
	public var singleTapGestureEnabled = true
	public var longPressGestureEnabled = true
	public var dragGestureEnabled = true
	public var rotationGestureEnabled = true
	public var doubleTapZoomGestureEnabled = true
	public var doubleTapDragZoomGestureEnabled = true
	public var pinchZoomGestureEnabled = true
	
	private var previousTouchesCount = 0
	private var previousCentroidInWindow: CGPoint?
	private var previousCentroid: CGPoint?
	private var previousDistance: CGFloat?
	
	private var centroidToCalculateVelocity: CGPoint?
	private var timestampToCalculateVelocity: TimeInterval?
	private var velocity: CGPoint = .zero
	private var targetOffset: Point = .zero
	private var displayLink: CADisplayLink?
	
	private var lastTouchTimestamp: TimeInterval = 0
	private var lastTouchLocation: CGPoint = .zero
	private var lastTouchTravelDistance: CGFloat = 0
	private var previousTouchEndCentroid: CGPoint?
	private var previousTouchTravelDistance: CGFloat = 0
	private var doubleTapDragZooming = false
	private var doubleTapDragZoomCenter: CGPoint = .zero
	private let doubleTapDragZoomDelay: TimeInterval = 0.26
	private let doubleTapDragZoomSpeed = 0.015
	private let tapHoldDuration = 0.25
	private var twoFingerTapTimestamp: TimeInterval?
	private var twoFingerTravelDistance: CGFloat = 0
	private var doubleTapZoomTimestamp: TimeInterval?
	
	private var singleTapPossible = false
	private var longPressWorkItem: DispatchWorkItem?
	private var trackingLayer: AnyHashable?
	
	private let initialRotationGestureThreshold: Radians = 0.25
	private var rotationGestureThreshold: Radians = 0.25
	private var rotationGestureDetected = false
	private var touchesBeganAngle: Radians?
	private var touchesBeganDistance: Double?
	private var previousAngle: Radians?
	
	private var touchesBeganTimestamps: [Int: TimeInterval] = [:]
	
	private var animation = SpringAnimation<Camera>(response: 0.4, dampingRatio: 1.0)
	
	public var projection = SphericalMercator()
	
	public var camera: Camera {
		get {
			return Camera(center: coordinates(at: contentBounds.center), zoom: animation.toValue.zoom, rotation: animation.toValue.rotation)
		}
		set {
			guard !newValue.zoom.isNearlyEqual(to: zoom) || !newValue.center.isNearlyEqual(to: coordinates(at: contentBounds.center)) || !newValue.rotation.isNearlyEqual(to: rotation) else {
				// nothing's changed — don't animate
				return
			}
			var value = newValue
			if newValue.zoom == zoom && animation.toValue.zoom != 0 {
				// if we doesn't seem to change zoom, use target zoom value
				value.zoom = animation.toValue.zoom
			}
			
			if animation.hasResolved() {
				animation.toValue = value.withRotationClose(to: animation.toValue)
				animation.stop(resolveImmediately: true, postValueChanged: true)
			} else {
				// if we have ongoing animation, redirect it to a new location
				//TODO: this may result in infinite animation if camera updates are more frequent than animation duration
				animation.toValue = value.withRotationClose(to: animation.toValue)
			}
		}
	}
	
	init(frame: CGRect, camera: Camera) {
		super.init(frame: frame)
		
		isMultipleTouchEnabled = true
		backgroundColor = .black

		self.camera = camera
		updateOffset(to: camera)
		
		animation.resolvingEpsilon = 0.0001
		animation.onValueChanged { [weak self] in self?.updateOffset(to: $0) }
	}
	
	
	func updateOffset(to camera: Camera) {
		stopDecelerating()
		zoom = camera.zoom
		offset = point(at: camera.center) - contentBounds.center
		rotation = camera.rotation.inRange
	}
	
	public func setCamera(_ newCamera: Camera, animated: Bool = true) {
		guard animated else {
			camera = newCamera.withRotationClose(to: camera)
			return
		}
		
		animation.updateValue(to: camera)
		animation.toValue = newCamera.withRotationClose(to: camera)
		
		animation.start()
	}
	
	public func coordinates(at screenPoint: Point) -> Coordinates {
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
	
	func didScroll() {
		
	}
	
	public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesBegan(touches, with: event)
		
		guard let event = event else {
			return
		}
		let centroidInWindow = event.centroid()
		let centroid = event.centroid(in: mapContentsView)
		let timeSincePreviousTap = event.timestamp - lastTouchTimestamp
		
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
			if event.activeTouches.count == 1 && longPressGestureEnabled {
				longPressWorkItem = DispatchWorkItem(block: {[weak self] in
					guard let self else { return }
					if let trackingLayer {
						onEndTracking(trackingLayer)
						self.trackingLayer = nil
					}
					onLongPress(point: previousCentroid ?? centroid)
				})
				DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapDragZoomDelay + 0.01, execute: longPressWorkItem!)
			}
		}
		
		if event.activeTouches.count == 2 && (lastTouchTravelDistance < 20 || touches.count == 2) {
			// detect possible two-finger tap
			twoFingerTapTimestamp = event.timestamp
		} else {
			twoFingerTapTimestamp = nil
		}
		
		if event.activeTouches.count == 2 {
			touchesBeganAngle = event.angle()
			touchesBeganDistance = event.activeTouches[0].location(in: nil).distance(to: event.activeTouches[1].location(in: nil))
			previousAngle = touchesBeganAngle
		}
		
		targetOffset = offset
		velocity = .zero
		centroidToCalculateVelocity = centroid
		timestampToCalculateVelocity = event.timestamp
		previousTouchTravelDistance = lastTouchTravelDistance
		lastTouchTravelDistance = 0
		singleTapPossible = false
		
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
			animation.stop()
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
		
		if previousTouchesCount != allTouches.count && (dragGestureEnabled || allTouches.count > 1) {
			offset += centroid - previousCentroid
			
			velocity = .zero
			centroidToCalculateVelocity = centroid
			timestampToCalculateVelocity = event.timestamp
		}
		
		if !doubleTapDragZooming && (dragGestureEnabled || allTouches.count > 1) {
			offset += (previousCentroid - centroid)
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
				
				let zoomCenterOnMap = offset + centroid
				let zoomChange = 1.0 - pow(2.0, zoom - previousZoom)
				
				offset -= zoomCenterOnMap * zoomChange
				
				twoFingerTravelDistance += abs(previousDistance - distance)
				rotationGestureThreshold = initialRotationGestureThreshold
				if !rotationGestureDetected {
					// the more we zoom, the less we likely to rotate
					rotationGestureThreshold *= (1.0 + min(twoFingerTravelDistance, 350.0) * 0.003)
					// the closer the fingers, the trickier it is to rotate
					rotationGestureThreshold *= (1.0 + max(260.0 - distance, 0.0) * 0.005)
					// the less we change distance between fingers, the more we likely want to rotate
					rotationGestureThreshold *= (1.0 + min(max(0, abs(distance - touchesBeganDistance) - 100), 200.0) * 0.005)
				}
			}
			
			if let previousAngle, let touchesBeganAngle, rotationGestureEnabled {
				if fabs(touchesBeganAngle - angle).inRange > rotationGestureThreshold {
					rotationGestureDetected = true
				}
				if rotationGestureDetected {
					rotation = (rotation + (angle - previousAngle)).inRange
				}
			}
			
			previousDistance = distance
			previousAngle = angle
		}
		
		if let timestamp = timestampToCalculateVelocity, let centroidToCalculateVelocity = centroidToCalculateVelocity {
			let time = event.timestamp - timestamp
			if time > 0.004 {
				//TODO: use more points to compute velocity
				velocity = (centroid - centroidToCalculateVelocity) / time
			}
		}
		
		if allTouches.count == 1 {
			if doubleTapDragZooming {
				let previousZoom = zoom
				zoom *= 1 + (previousCentroidInWindow - centroidInWindow).y / zoom * doubleTapDragZoomSpeed
				
				let zoomCenterOnMap = offset + doubleTapDragZoomCenter
				let zoomChange = 1.0 - pow(2.0, zoom - previousZoom)
				
				offset -= zoomCenterOnMap * zoomChange
			}
			
			lastTouchTravelDistance += (previousCentroid - centroid).length
		}
		
		targetOffset = offset
		animation.toValue.zoom = zoom
		animation.toValue.rotation = rotation
		animation.stop()
		didScroll()
		
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
			let zoomCenterOnMap = offset + contentBounds.center + ((previousCentroid ?? contentBounds.center) - contentBounds.center) * 0.5
			
			setCamera(Camera(center: projection.coordinates(from: zoomCenterOnMap, at: zoom), zoom: zoom - 1, rotation: rotation))
		}
		
		if activeTouches.count < 2 {
			previousDistance = nil
			previousAngle = nil
			touchesBeganAngle = nil
			rotationGestureDetected = false
			rotationGestureThreshold = initialRotationGestureThreshold
		}
		
		longPressWorkItem?.cancel()
		
		if activeTouches.isEmpty && touches.count == 1 {
			let timeSinceTouchBegan = event.timestamp - (touchesBeganTimestamps[touches.first!.hash] ?? 0)
			// zoom in animated with double-tap gesture
			let timeSincePreviousTap = event.timestamp - lastTouchTimestamp
			let distanceBetweenLastTwoTouches = (previousTouchEndCentroid ?? .zero).distance(to: previousCentroid ?? .zero)
			if lastTouchTravelDistance < 30 && previousTouchTravelDistance < 30 && timeSincePreviousTap < doubleTapDragZoomDelay && distanceBetweenLastTwoTouches < 30 && twoFingerTapTimestamp == nil && doubleTapZoomGestureEnabled {
				let zoomCenterOnMap = offset + contentBounds.center + ((previousCentroid ?? contentBounds.center) - contentBounds.center) * 0.5
				doubleTapZoomTimestamp = event.timestamp
				
				setCamera(Camera(center: projection.coordinates(from: zoomCenterOnMap, at: zoom), zoom: zoom + 1, rotation: rotation))
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
			
			if dragGestureEnabled {
				targetOffset = offset - velocity * 0.1
				if velocity != .zero {
					startDecelerating()
				}
			}
			
			previousTouchEndCentroid = previousCentroid
			previousCentroid = nil
			twoFingerTravelDistance = 0
			doubleTapDragZooming = false
			
			lastTouchTimestamp = event.timestamp
			lastTouchLocation = touches.first!.location(in: mapContentsView)
		} else {
			previousCentroid = activeTouches.centroid(in: mapContentsView)
		}
		
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
	}
	
	var mapContentsView: UIView {
		self
	}
	
	private func startDecelerating() {
		displayLink?.invalidate()
		displayLink = CADisplayLink(target: self, selector: #selector(decelerate))
		displayLink?.add(to: .current, forMode: .common)
	}
	
	func stopDecelerating() {
		guard displayLink != nil else {
			return
		}
		targetOffset = offset
		displayLink?.invalidate()
		displayLink = nil
	}
	
	@objc private func decelerate() {
		offset += (targetOffset - offset) * 0.15
		didScroll()
		
		if (offset - targetOffset).length < 5 {
			stopDecelerating()
		}
	}
	
	func onSingleTap(point: CGPoint) {
		// override if necessary
	}
	
	func onLongPress(point: CGPoint) {
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
	
	var contentBounds: CGRect {
		bounds.inset(by: contentInset)
	}
}


private extension Camera {
	func withRotationClose(to camera: Camera) -> Camera {
		var adjusted = self

		while abs(adjusted.rotation - camera.rotation + 2.0 * .pi) < abs(adjusted.rotation - camera.rotation)  {
			adjusted.rotation += 2.0 * .pi
		}
		while abs(adjusted.rotation - camera.rotation - 2.0 * .pi) < abs(adjusted.rotation - camera.rotation)  {
			adjusted.rotation -= 2.0 * .pi
		}
		return adjusted
	}
}
