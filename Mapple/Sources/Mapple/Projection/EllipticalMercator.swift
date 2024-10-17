//
//  EllipticalMercator.swift
//  Mapple
//
//  Created by Pavel Alexeev on 15.10.2024.
//


import Foundation

public struct EllipticalMercator: Projection {
	public let tileSize: Int
	public let e: Double
	
	private let d2, d4, d6, d8: Double
	
	public init(tileSize: Int = 256, e: Double = 0.0818191908426) {
		self.tileSize = tileSize
		self.e = e
		
		let e2 = e * e
		let e4 = e2 * e2
		let e6 = e4 * e2
		let e8 = e4 * e4
		// Approximate calculation, taken from https://geomatics.cc/legacy-files/mercator.pdf (5.110)
		d2 = e2 / 2.0 + 5.0 * e4 / 24.0 + e6 / 12.0 + 13.0 * e8 / 360.0
		d4 = 7.0 * e4 / 48.0 + 29.0 * e6 / 240.0 + 811.0 * e8 / 11520.0
		d6 = 7.0 * e6 / 120.0 + 81.0 * e8 / 1120.0
		d8 = 4279.0 * e8 / 161280.0
	}
	
	public func point(at zoom: Double, from coordinates: Coordinates) -> PointOffset {
		let tiles = pow(2, zoom)
		let circumference = tiles * Double(tileSize)
		let radius = circumference / (2 * .pi)
		let falseEasting = -1.0 * circumference / 2.0
		let x = radius * coordinates.longitude.radians - falseEasting
		
		let rho = pow(2, zoom + 8) / 2
		let latitude = coordinates.latitude.radians
		let sinLatitude = sin(latitude)
		let phi = (1 - e * sinLatitude) / (1 + e * sinLatitude)
		let theta = tan(Double.pi / 4 + latitude / 2) * pow(phi, e / 2)
		let y = rho * (1 - log(theta) / .pi)
		
		return Point(x: x, y: y)
	}
	
	public func coordinates(from point: PointOffset, at zoom: Double) -> Coordinates {
		let tiles = pow(2, zoom)
		let circumference = tiles * Double(tileSize)
		let radius = circumference / (2 * .pi)
		let falseEasting = -1.0 * circumference / 2.0
		let falseNorthing = circumference / 2.0
		
		let spherical = -(2 * atan(exp((point.y + falseEasting) / radius)) - (.pi / 2))
		
		// Approximate calculation
		let latitude = spherical + d2 * sin(2 * spherical) + d4 * sin(4 * spherical) + d6 * sin(6 * spherical) + d8 * sin(8 * spherical)
		
//
//		Precise calculation
//
//		let ts = exp((point.y + falseEasting) / radius);
//		var latitude = .pi/2 - 2 * atan(ts);
//		var dphi = 1.0
//		var i = 0
//		while ((abs(dphi) > 0.000000001) && (i < 15))
//		{
//			let con = e * sin(latitude)
//			dphi = .pi/2 - 2 * atan(ts * pow((1.0 - con) / (1.0 + con), e/2)) - latitude
//			latitude += dphi
//			i += 1
//		}
		
		return Coordinates(
			latitude: latitude.degrees,
			longitude: Double(point.x - falseNorthing).degrees / radius
		)
	}
}

extension EllipticalMercator {
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
		
		let rho = pow(2, data.zoom + 8) / 2
		let latitude = coordinates.latitude.radians
		let phi = (1 - e * sin(latitude)) / (1 + e * sin(latitude))
		let theta = tan(Double.pi / 4 + latitude / 2) * pow(phi, e / 2)
		let y = rho * (1 - log(theta) / .pi)
		
		return Point(x: x, y: y)
	}
	
	public struct ZoomData {
		let zoom: Double
		let radius: Double
		let falseEasting: Double
		let falseNorthing: Double
	}
}
