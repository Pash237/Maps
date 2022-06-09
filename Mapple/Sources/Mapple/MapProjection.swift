//
//  WebProjection.swift
//  maps
//
//  Created by Pavel Alexeev on 01.06.2022.
//

import Foundation

protocol Projection {
	func point(at zoom: Double, tileSize: Int, from coordinates: Coordinates) -> Point
	func coordinates(from point: Point, at zoom: Double, tileSize: Int) -> Coordinates
}

struct SphericalMercator: Projection {
	func point(at zoom: Double, tileSize: Int, from coordinates: Coordinates) -> Point {
		let tiles = pow(2, zoom)
		let circumference = tiles * Double(tileSize)
		let radius = circumference / (2 * .pi)
		let falseEasting = -1.0 * circumference / 2.0
		let falseNorthing = circumference / 2.0
		let x = radius * coordinates.longitude.radians - falseEasting
		let y = ((radius / 2.0 * log((1.0 + sin(coordinates.latitude.radians)) / (1.0 - sin(coordinates.latitude.radians)))) - falseNorthing) * -1
		
		
		return Point(x: x, y: y)
	}
	
	func coordinates(from point: Point, at zoom: Double, tileSize: Int) -> Coordinates {
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
	func convert(point: Point, from fromZoom: Double, to toZoom: Double) -> Point {
		let scale = pow(2.0, toZoom - fromZoom)
		return Point(
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
