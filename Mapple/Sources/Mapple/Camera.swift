//
//  Camera.swift
//  maps
//
//  Created by Pavel Alexeev on 09.06.2022.
//

import Foundation
import CoreGraphics

public struct Camera: Codable {
	public var center: Coordinates
	public var zoom: Double
	
	public init(center: Coordinates, zoom: Double) {
		self.center = center
		self.zoom = zoom
	}
	
	public static func fitting(_ coordinateBounds: CoordinateBounds, with bounds: CGRect, padding: Double = 0, projection: Projection = SphericalMercator()) -> Camera {
		let maxZoom = 20.0
		let boundsAtMaxZoom = projection.point(at: maxZoom, tileSize: 256, from: coordinateBounds.southeast) - projection.point(at: maxZoom, tileSize: 256, from: coordinateBounds.northwest)
		
		
		let scale: Double = max(
			boundsAtMaxZoom.x / (bounds.width - padding*2),
			boundsAtMaxZoom.y / (bounds.height - padding*2)
		)
		let zoom = maxZoom - log2(scale)
		
		return Camera(center: coordinateBounds.center, zoom: zoom)
	}
	
	public static func fitting(coordinates: [Coordinates], with bounds: CGRect, padding: Double = 0, projection: Projection = SphericalMercator()) -> Camera {
		guard !coordinates.isEmpty else {
			return Camera(center: Coordinates(50, 20), zoom: 3)
		}
		return Camera.fitting(CoordinateBounds(coordinates: coordinates), with: bounds, padding: padding, projection: projection)
	}
	
	public func coordinateBounds(with bounds: CGRect, projection: Projection = SphericalMercator(), tileSize: Int = 256) -> CoordinateBounds {
		let offset = projection.point(at: zoom, tileSize: tileSize, from: center)
		let topLeft = offset - bounds.size/2
		let bottomRight = offset + bounds.size/2
		
		return CoordinateBounds(
			northeast: projection.coordinates(from: topLeft, at: zoom, tileSize: tileSize),
			southwest: projection.coordinates(from: bottomRight, at: zoom, tileSize: tileSize)
		)
	}
}
