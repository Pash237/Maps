//
//  WebProjection.swift
//  maps
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

public struct SphericalMercator: Projection {
	public let tileSize: Int
	
	public init(tileSize: Int = 256) {
		self.tileSize = tileSize
	}
	
	public func point(at zoom: Double, from coordinates: Coordinates) -> PointOffset {
		let tiles = pow(2, zoom)
		let circumference = tiles * Double(tileSize)
		let radius = circumference / (2 * .pi)
		let falseEasting = -1.0 * circumference / 2.0
		let falseNorthing = circumference / 2.0
		let x = radius * coordinates.longitude.radians - falseEasting
		let y = ((radius / 2.0 * log((1.0 + sin(coordinates.latitude.radians)) / (1.0 - sin(coordinates.latitude.radians)))) - falseNorthing) * -1
		
		
		return Point(x: x, y: y)
	}
	
	public func coordinates(from point: PointOffset, at zoom: Double) -> Coordinates {
		let tiles = pow(2, zoom)
		let circumference = tiles * Double(tileSize)
		let radius = circumference / (2 * .pi)
		let falseEasting = -1.0 * circumference / 2.0
		let falseNorthing = circumference / 2.0
		return Coordinates(
			latitude: -(2 * atan(exp((point.y + falseEasting) / radius)) - (.pi / 2)).degrees,
			longitude: Double(point.x - falseNorthing).degrees / radius
		)
	}
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
