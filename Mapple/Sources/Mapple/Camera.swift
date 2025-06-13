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
	
	public static func fitting(_ coordinateBounds: CoordinateBounds, with bounds: CGRect, padding: Double = 0, rotation: Double = 0, maxZoom: Double = 17.0, projection: Projection = SphericalMercator()) -> Camera {
		guard abs(coordinateBounds.southwest.latitude - coordinateBounds.northeast.latitude) > 0.000001,
			  abs(coordinateBounds.southwest.longitude - coordinateBounds.northeast.longitude) > 0.000001 else {
			print("Warning! Could not fit \(coordinateBounds)")
			return Camera(center: coordinateBounds.center, zoom: 15)
		}
		let boundsAtMaxZoom = projection.point(at: maxZoom, from: coordinateBounds.southeast) - projection.point(at: maxZoom, from: coordinateBounds.northwest)
		
		let scale: Double = max(
			boundsAtMaxZoom.x / (bounds.width - padding*2),
			boundsAtMaxZoom.y / (bounds.height - padding*2)
		)
		let zoom = maxZoom - log2(scale)
		
		return Camera(center: coordinateBounds.center, zoom: zoom, rotation: rotation)
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


extension Camera {
	func withRotationClose(to rotation: Radians) -> Camera {
		var adjusted = self

		while abs(adjusted.rotation - rotation + 2.0 * .pi) < abs(adjusted.rotation - rotation)  {
			adjusted.rotation += 2.0 * .pi
		}
		while abs(adjusted.rotation - rotation - 2.0 * .pi) < abs(adjusted.rotation - rotation)  {
			adjusted.rotation -= 2.0 * .pi
		}
		return adjusted
	}
	
	public func isNearlyEqual(to camera: Camera) -> Bool {
		abs(center.latitude - camera.center.latitude) < 0.000001 &&
		abs(center.longitude - camera.center.longitude) < 0.000001 &&
		abs(zoom - camera.zoom) < 0.001 &&
		abs(rotation - camera.rotation) < 0.001
	}
}

extension Camera: Equatable {
	static public func == (lhs: Camera, rhs: Camera) -> Bool {
		lhs.isNearlyEqual(to: rhs)
	}
}

extension Camera: CustomStringConvertible {
	public var description: String {
		"\(center) @\(zoom)" + (rotation != 0 ? " \(rotation)°" : "")
	}
}
