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
	
	private var previousTouchesCount = 0
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
	private let doubleTapDragZoomDelay: TimeInterval = 0.3
	private let doubleTapDragZoomSpeed = 0.015
	private var twoFingerTapTimestamp: TimeInterval?
	private var twoFingerTravelDistance: CGFloat = 0
	private var doubleTapZoomTimestamp: TimeInterval?
	
	private var singleTapPossible: Bool = false
	
	private var touchesBeganTimestamps: [Int: TimeInterval] = [:]
	
	private var animation = SpringAnimation<Camera>(response: 0.4, dampingRatio: 1.0)
	
	public var projection = SphericalMercator()
	
	public var camera: Camera {
		get {
			return Camera(center: coordinates(at: bounds.center), zoom: zoom)
		}
		set {
			guard !newValue.zoom.isNearlyEqual(to: zoom) || !newValue.center.isNearlyEqual(to: coordinates(at: bounds.center)) else {
				// nothing's changed — don't animate
				return
			}
			var value = newValue
			if newValue.zoom == zoom && animation.toValue.zoom != 0 {
				// if we doesn't seem to change zoom, use target zoom value
				value.zoom = animation.toValue.zoom
			}
			
			if animation.hasResolved() {
				animation.toValue = value
				animation.stop(resolveImmediately: true, postValueChanged: true)
			} else {
				// if we have ongoing animation, redirect it to a new location
				//TODO: this may result in infinite animation if camera updates are more frequent than animation duration
				animation.toValue = value
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
		offset = point(at: camera.center) - bounds.center
	}
	
	public func setCamera(_ newCamera: Camera, animated: Bool = true) {
		guard animated else {
			camera = newCamera
			return
		}
		
		animation.updateValue(to: camera)
		animation.toValue = newCamera
		
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
		CoordinateBounds(northeast: coordinates(at: CGPoint(bounds.width, 0)),
						 southwest: coordinates(at: CGPoint(0, bounds.height)))
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
		let centroid = event.centroid(in: self)
		let timeSincePreviousTap = event.timestamp - lastTouchTimestamp
		
		previousCentroid = centroid
		if event.activeTouches.count == 1 {
			previousTouchesCount = event.activeTouches.count
		}
		
		for touch in touches {
			touchesBeganTimestamps[touch.hash] = touch.timestamp
		}
		
		// detect double tap
		if event.activeTouches.count == 1 && lastTouchTravelDistance < 50 && timeSincePreviousTap < doubleTapDragZoomDelay && (centroid - lastTouchLocation).length < 50 && twoFingerTapTimestamp == nil && doubleTapZoomTimestamp == nil {
			doubleTapDragZooming = true
			doubleTapDragZoomCenter = centroid
		} else {
			doubleTapDragZooming = false
		}
		
		if event.activeTouches.count == 2 && (lastTouchTravelDistance < 30 || touches.count == 2) {
			// detect possible two-finger tap
			twoFingerTapTimestamp = event.timestamp
		} else {
			twoFingerTapTimestamp = nil
		}
		
		targetOffset = offset
		velocity = .zero
		centroidToCalculateVelocity = centroid
		timestampToCalculateVelocity = event.timestamp
		previousTouchTravelDistance = lastTouchTravelDistance
		lastTouchTravelDistance = 0
		singleTapPossible = false
		
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
			  let previousCentroid = previousCentroid else {
			return
		}
		
		var allTouches = event.activeTouches
		
		let centroid = event.centroid(in: self)
		
		if previousTouchesCount != allTouches.count {
			offset += centroid - previousCentroid
			
			velocity = .zero
			centroidToCalculateVelocity = centroid
			timestampToCalculateVelocity = event.timestamp
		}
		
		if !doubleTapDragZooming {
			offset += (previousCentroid - centroid)
		}
		
		if allTouches.count >= 2 {
			allTouches.sort(by: {
				touchesBeganTimestamps[$0.hash] ?? $0.timestamp > touchesBeganTimestamps[$1.hash] ?? $1.timestamp
			})
			
			let distance = allTouches[0].location(in: self).distance(to: allTouches[1].location(in: self))
			
			if let previousDistance = previousDistance,
			   previousTouchesCount == allTouches.count,
			   abs(previousDistance - distance) < 100 /* deal with sometimes happening touch issues */
			{
				let previousZoom = zoom
				zoom *= 1 + (distance/previousDistance - 1) / zoom*1.5
				
				let zoomCenterOnMap = offset + centroid
				let zoomChange = 1.0 - pow(2.0, zoom - previousZoom)
				
				offset -= zoomCenterOnMap * zoomChange
				
				twoFingerTravelDistance += abs(previousDistance - distance)
			}
			
			previousDistance = distance
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
				zoom *= 1 + (previousCentroid - centroid).y / zoom * doubleTapDragZoomSpeed
				
				let zoomCenterOnMap = offset + doubleTapDragZoomCenter
				let zoomChange = 1.0 - pow(2.0, zoom - previousZoom)
				
				offset -= zoomCenterOnMap * zoomChange
			}
			
			lastTouchTravelDistance += (previousCentroid - centroid).length
		}
		
		targetOffset = offset
		animation.stop()
		didScroll()
		
		self.previousCentroid = centroid
		previousTouchesCount = allTouches.count
		centroidToCalculateVelocity = centroid
		timestampToCalculateVelocity = event.timestamp
		singleTapPossible = false
	}
	
	public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesEnded(touches, with: event)
		
		guard let event = event else {
			return
		}
		
		let activeTouches = event.activeTouches
		
		// zoom out animated with two finger tap gesture
		if let twoFingerTapTimestamp = twoFingerTapTimestamp, activeTouches.isEmpty, event.timestamp - twoFingerTapTimestamp < 0.3, twoFingerTravelDistance < 4 {
			let zoomCenterOnMap = offset + bounds.center + ((previousCentroid ?? bounds.center) - bounds.center) * 0.5
			
			setCamera(Camera(center: projection.coordinates(from: zoomCenterOnMap, at: zoom), zoom: zoom - 1))
		}
		
		if activeTouches.count < 2 {
			previousDistance = nil
		}
		
		if activeTouches.isEmpty && touches.count == 1 {
			// zoom in animated with double-tap gesture
			let timeSincePreviousTap = event.timestamp - lastTouchTimestamp
			let distanceBetweenLastTwoTouches = (previousTouchEndCentroid ?? .zero).distance(to: previousCentroid ?? .zero)
			if lastTouchTravelDistance < 30 && previousTouchTravelDistance < 30 && timeSincePreviousTap < doubleTapDragZoomDelay && distanceBetweenLastTwoTouches < 30 && twoFingerTapTimestamp == nil {
				let zoomCenterOnMap = offset + bounds.center + ((previousCentroid ?? bounds.center) - bounds.center) * 0.5
				doubleTapZoomTimestamp = event.timestamp
				
				setCamera(Camera(center: projection.coordinates(from: zoomCenterOnMap, at: zoom), zoom: zoom + 1))
			} else {
				doubleTapZoomTimestamp = nil
			}
			
			if lastTouchTravelDistance == 0 && (timeSincePreviousTap > doubleTapDragZoomDelay || distanceBetweenLastTwoTouches > 30) {
				singleTapPossible = true
				DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapDragZoomDelay + 0.01) {[weak self] in
					guard let self else { return }
					if self.singleTapPossible {
						self.onSingleTap(point: self.lastTouchLocation)
						self.singleTapPossible = false
					}
				}
			}
			
			if velocity.length < 400 {
				velocity = .zero
			}
			
			targetOffset = offset - velocity * 0.1
			if velocity != .zero {
				startDecelerating()
			}
			
			previousTouchEndCentroid = previousCentroid
			previousCentroid = nil
			twoFingerTravelDistance = 0
			doubleTapDragZooming = false
			
			lastTouchTimestamp = event.timestamp
			lastTouchLocation = touches.first?.location(in: self) ?? .zero
		} else {
			previousCentroid = activeTouches.centroid(in: self)
		}
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
}

extension UIEvent {
	var activeTouches: [UITouch] {
		(allTouches ?? [])
			.filter {$0.phase != .ended && $0.phase != .cancelled}
	}
	
	func centroid(in view: UIView? = nil, phases: Set<UITouch.Phase> = [.began, .moved, .stationary]) -> CGPoint {
		(allTouches ?? []).centroid(in: view, phases: phases)
	}
}

extension Collection where Element == UITouch {
	func centroid(in view: UIView? = nil, phases: Set<UITouch.Phase> = [.began, .moved, .stationary]) -> CGPoint {
		var centroid = CGPoint.zero
		var touchesCount = 0
		for touch in self {
			if !phases.contains(touch.phase) {
				continue
			}

			let point = touch.location(in: view)
			centroid.x += point.x
			centroid.y += point.y
			touchesCount += 1
		}
		if touchesCount == 0 {
			if !phases.contains(.ended) {
				return self.centroid(in: view, phases: [.began, .moved, .stationary, .ended, .cancelled])
			} else {
				return CGPoint.zero
				
			}
		}
		centroid.x /= CGFloat(touchesCount)
		centroid.y /= CGFloat(touchesCount)
		return centroid
	}
}
