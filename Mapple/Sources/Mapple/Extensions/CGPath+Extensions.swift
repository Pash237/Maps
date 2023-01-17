//
//  File.swift
//  
//
//  Created by Pavel Alexeev on 17.01.2023.
//

import CoreGraphics

extension CGPath {
	func forEach( body: @escaping @convention(block) (CGPathElement) -> Void) {
		typealias Body = @convention(block) (CGPathElement) -> Void
		let callback: @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CGPathElement>) -> Void = { (info, element) in
			let body = unsafeBitCast(info, to: Body.self)
			body(element.pointee)
		}
		let unsafeBody = unsafeBitCast(body, to: UnsafeMutableRawPointer.self)
		self.apply(info: unsafeBody, function: unsafeBitCast(callback, to: CGPathApplierFunction.self))
	}
	
	func getPoints() -> [CGPoint] {
		var arrayPoints : [CGPoint]! = [CGPoint]()
		self.forEach { element in
			switch (element.type) {
			case CGPathElementType.moveToPoint:
				arrayPoints.append(element.points[0])
			case .addLineToPoint:
				arrayPoints.append(element.points[0])
			case .addQuadCurveToPoint:
				arrayPoints.append(element.points[0])
				arrayPoints.append(element.points[1])
			case .addCurveToPoint:
				arrayPoints.append(element.points[0])
				arrayPoints.append(element.points[1])
				arrayPoints.append(element.points[2])
			default: break
			}
		}
		return arrayPoints
	}
}
