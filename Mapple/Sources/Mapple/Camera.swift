//
//  Camera.swift
//  maps
//
//  Created by Pavel Alexeev on 09.06.2022.
//

import Foundation
import CoreGraphics

public typealias Radians = Double

public struct Camera: Codable {
	public var center: Coordinates
	public var zoom: Double
	public var rotation: Radians
	
	public init(center: Coordinates, zoom: Double, rotation: Radians = 0.0) {
		self.center = center
		self.zoom = zoom
		self.rotation = rotation
	}
	
	public static func fitting(_ coordinateBounds: CoordinateBounds, with bounds: CGRect, padding: Double = 0, projection: Projection = SphericalMercator()) -> Camera {
		let maxZoom = 20.0
		let boundsAtMaxZoom = projection.point(at: maxZoom, from: coordinateBounds.southeast) - projection.point(at: maxZoom, from: coordinateBounds.northwest)
		
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
	
	public func coordinateBounds(with bounds: CGRect, projection: Projection = SphericalMercator()) -> CoordinateBounds {
		let offset = projection.point(at: zoom, from: center)
		let topLeft = offset - bounds.size/2
		let bottomRight = offset + bounds.size/2
		
		return CoordinateBounds(
			northwest: projection.coordinates(from: topLeft, at: zoom),
			southeast: projection.coordinates(from: bottomRight, at: zoom)
		)
	}
	
	public func with(center: Coordinates) -> Camera {
		var camera = self
		camera.center = center
		return camera
	}
	
	public func with(zoom: Double) -> Camera {
		var camera = self
		camera.zoom = zoom
		return camera
	}
	
	public func with(rotation: Double) -> Camera {
		var camera = self
		camera.rotation = rotation
		return camera
	}
}
