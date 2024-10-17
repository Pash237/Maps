//
//  WebProjection.swift
//  Mapple
//
//  Created by Pavel Alexeev on 01.06.2022.
//

import Foundation

public typealias PointOffset = Point

public protocol Projection {
	var tileSize: Int { get }
	func point(at zoom: Double, from coordinates: Coordinates) -> PointOffset
	func coordinates(from point: PointOffset, at zoom: Double) -> Coordinates
}

extension Projection {
	public func convert(point: PointOffset, from fromZoom: Double, to toZoom: Double) -> PointOffset {
		let scale = pow(2.0, toZoom - fromZoom)
		return PointOffset(
			x: point.x * scale,
			y: point.y * scale
		)
	}
}

extension Double {
	var radians: Double {
		self * .pi / 180.0
	}
	var degrees: Double {
		self * 180.0 / .pi
	}
}
