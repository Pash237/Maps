//
//  CGPoint+Extensions.swift
//  ActiveTrip
//
//  Created by Pavel Alexeev on 27.03.2022.
//

import Foundation
import CoreGraphics

public typealias Point = CGPoint

extension CGPoint {
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
	
	var angle: CGFloat {
		atan2(y, x)
	}
}


func *(lhs: CGPoint, rhs: CGFloat) -> CGPoint {
	CGPoint(x: lhs.x*rhs, y: lhs.y*rhs)
}

func /(lhs: CGPoint, rhs: CGFloat) -> CGPoint {
	CGPoint(x: lhs.x/rhs, y: lhs.y/rhs)
}

func +(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
	CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

func -(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
	CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}


func +(lhs: CGPoint, rhs: CGSize) -> CGPoint {
	CGPoint(x: lhs.x + rhs.width, y: lhs.y + rhs.height)
}

func -(lhs: CGPoint, rhs: CGSize) -> CGPoint {
	CGPoint(x: lhs.x - rhs.width, y: lhs.y - rhs.height)
}

func *(lhs: CGSize, rhs: CGFloat) -> CGSize {
	CGSize(width: lhs.width*rhs, height: lhs.height*rhs)
}

func /(lhs: CGSize, rhs: CGFloat) -> CGSize {
	CGSize(width: lhs.width/rhs, height: lhs.height/rhs)
}

func +=(lhs: inout CGPoint, rhs: CGPoint) {
	lhs = lhs + rhs
}

func -=(lhs: inout CGPoint, rhs: CGPoint) {
	lhs = lhs - rhs
}


extension CGRect {
	static let placeholder = CGRect(x: 0, y: 0, width: 100, height: 100)
}



extension CGRect {
	var center: CGPoint {
		CGPoint(x: midX, y: midY)
	}
}
