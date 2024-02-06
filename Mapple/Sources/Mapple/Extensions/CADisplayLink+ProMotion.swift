//
//  CADisplayLink+ProMotion.swift
//  
//
//  Created by Pavel Alexeev on 22.12.2023.
//

import UIKit

extension CADisplayLink {
	private static let sharedDraggingDisplayLink: CADisplayLink = {
		let displayLink = CADisplayLink(target: DraggingDisplayLinkHandler.shared,
										selector: #selector(DraggingDisplayLinkHandler.onDisplayLink(_:)))
		displayLink.add(to: .current, forMode: .common)
		if #available(iOS 15.0, *) {
			displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
		}
		displayLink.isPaused = true
		return displayLink
	}()
	
	static func enableProMotion(timeout: TimeInterval = 0.1) {
		if sharedDraggingDisplayLink.isPaused {
			sharedDraggingDisplayLink.isPaused = false
		}
		DraggingDisplayLinkHandler.shared.disableTime = CFAbsoluteTimeGetCurrent() + timeout
	}
}

private class DraggingDisplayLinkHandler {
	static let shared = DraggingDisplayLinkHandler()
	var disableTime: TimeInterval = .greatestFiniteMagnitude
	
	@objc func onDisplayLink(_ displayLink: CADisplayLink) {
		if CFAbsoluteTimeGetCurrent() > disableTime {
			displayLink.isPaused = true
		}
	}
}
