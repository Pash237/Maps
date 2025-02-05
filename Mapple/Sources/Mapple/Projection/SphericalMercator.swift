//
//  SphericalMercator.swift
//  Mapple
//
//  Created by Pavel Alexeev on 15.10.2024.
//

import Foundation

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

extension SphericalMercator {
	public func zoomData(for zoom: Double) -> ZoomData {
		let tiles = pow(2, zoom)
		let circumference = tiles * Double(tileSize)
		let radius = circumference / (2 * .pi)
		let falseEasting = -1.0 * circumference / 2.0
		let falseNorthing = circumference / 2.0
		return ZoomData(zoom: zoom, radius: radius, falseEasting: falseEasting, falseNorthing: falseNorthing)
	}
	
	public func point(withZoomData data: ZoomData, from coordinates: Coordinates) -> PointOffset {
		let x = data.radius * coordinates.longitude.radians - data.falseEasting
		let sinLatitude = sin(coordinates.latitude.radians)
		let y = ((data.radius / 2.0 * log((1.0 + sinLatitude) / (1.0 - sinLatitude))) - data.falseNorthing) * -1
		return Point(x: x, y: y)
	}
	
	public struct ZoomData {
		let zoom: Double
		let radius: Double
		let falseEasting: Double
		let falseNorthing: Double
	}
}
