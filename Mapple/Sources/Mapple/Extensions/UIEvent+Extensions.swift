//
//  UIEvent+Extensions.swift
//  
//
//  Created by Pavel Alexeev on 06.07.2023.
//

import UIKit

extension UIEvent {
	var activeTouches: [UITouch] {
		(allTouches ?? [])
			.filter {$0.phase != .ended && $0.phase != .cancelled}
	}
	
	func centroid(in view: UIView? = nil, phases: Set<UITouch.Phase> = [.began, .moved, .stationary]) -> CGPoint {
		(allTouches ?? []).centroid(in: view, phases: phases)
	}
	
	func angle(in view: UIView? = nil, phases: Set<UITouch.Phase> = [.began, .moved, .stationary]) -> Radians? {
		(allTouches ?? []).angle(in: view, phases: phases)
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
	
	func angle(in view: UIView? = nil, phases: Set<UITouch.Phase> = [.began, .moved, .stationary]) -> Radians? {
		let filtered = filter {
			phases.contains($0.phase)
		}
		guard filtered.count >= 2 else {
			return nil
		}
		let location0 = filtered[filtered.startIndex].location(in: view)
		let location1 = filtered[filtered.index(filtered.startIndex, offsetBy: 1)].location(in: view)
		
		return atan2(location1.y - location0.y, location1.x - location0.x)
	}
}
