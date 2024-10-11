//
//  CGPoint+Extensions.swift
//  ActiveTrip
//
//  Created by Pavel Alexeev on 27.03.2022.
//

import Foundation
import CoreGraphics

public typealias Point = CGPoint

public extension CGPoint {
	func angleWith(point: CGPoint) -> CGFloat {
		atan2(y - point.y, x - point.x)
	}
	
	func subtract(point: CGPoint) -> CGPoint {
		CGPoint(x: x - point.x, y: y - point.y)
	}
	
	func distance(to point: CGPoint) -> CGFloat {
		hypot(x - point.x, y - point.y)
	}
	
	var length: CGFloat {
		hypot(x, y)
	}
	
	var maxDimension: CGFloat {
		max(abs(x), abs(y))
	}
	
	var angle: CGFloat {
		atan2(y, x)
	}
	
	init(_ x: CGFloat, _ y: CGFloat) {
		self.init(x: x, y: y)
	}
}


public func *(lhs: CGPoint, rhs: CGFloat) -> CGPoint {
	CGPoint(x: lhs.x*rhs, y: lhs.y*rhs)
}

public func /(lhs: CGPoint, rhs: CGFloat) -> CGPoint {
	CGPoint(x: lhs.x/rhs, y: lhs.y/rhs)
}

public func +(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
	CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

public func -(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
	CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}


public func +(lhs: CGPoint, rhs: CGSize) -> CGPoint {
	CGPoint(x: lhs.x + rhs.width, y: lhs.y + rhs.height)
}

public func -(lhs: CGPoint, rhs: CGSize) -> CGPoint {
	CGPoint(x: lhs.x - rhs.width, y: lhs.y - rhs.height)
}

public func *(lhs: CGSize, rhs: CGFloat) -> CGSize {
	CGSize(width: lhs.width*rhs, height: lhs.height*rhs)
}

public func /(lhs: CGSize, rhs: CGFloat) -> CGSize {
	CGSize(width: lhs.width/rhs, height: lhs.height/rhs)
}

public func +=(lhs: inout CGPoint, rhs: CGPoint) {
	lhs = lhs + rhs
}

public func -=(lhs: inout CGPoint, rhs: CGPoint) {
	lhs = lhs - rhs
}


extension CGRect {
	static let placeholder = CGRect(x: 0, y: 0, width: 100, height: 100)
}


public extension CGRect {
	var center: CGPoint {
		CGPoint(x: midX, y: midY)
	}
	
	init(left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
		self.init(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
	}
}

public extension Radians {
	var inRange: Radians {
		var angle = self
		while angle > .pi {
			angle -= .pi * 2
		}
		while angle <= -.pi {
			angle += .pi * 2
		}
		return angle
	}
}
