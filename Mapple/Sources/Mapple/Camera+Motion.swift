//
//  Camera+Motion.swift
//  
//
//  Created by Pavel Alexeev on 21.07.2022.
//

import Foundation
import Motion
import CoreLocation

extension Camera: SIMDRepresentable {
	public static func == (lhs: Camera, rhs: Camera) -> Bool {
		lhs.center == rhs.center && lhs.zoom == rhs.zoom && lhs.rotation == rhs.rotation
	}
	
	public static var zero: Camera {
		Camera(center: Coordinates(0, 0), zoom: 0, rotation: 0)
	}

	public typealias SIMDType = SIMD4<Double>

	@inlinable public init(_ simdRepresentation: SIMD4<Double>) {
		self.init(center: Coordinates(simdRepresentation[0], simdRepresentation[1]), zoom: simdRepresentation[2], rotation: simdRepresentation[3])
	}

	@inlinable public func simdRepresentation() -> SIMD4<Double> {
		SIMD4(center.latitude, center.longitude, zoom, rotation)
	}

	@inlinable public static func < (lhs: Camera, rhs: Camera) -> Bool {
		lhs.center.latitude < rhs.center.latitude && lhs.center.longitude < rhs.center.longitude && lhs.zoom < rhs.zoom && lhs.rotation < rhs.rotation
	}
}

