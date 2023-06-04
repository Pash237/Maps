//
//  Camera+Motion.swift
//  
//
//  Created by Pavel Alexeev on 21.07.2022.
//

import Foundation
import Motion


extension Camera: SIMDRepresentable {
	public static func == (lhs: Camera, rhs: Camera) -> Bool {
		lhs.center == rhs.center && lhs.zoom == rhs.zoom
	}
	
	public static var zero: Camera {
		Camera(center: Coordinates(0, 0), zoom: 0)
	}

	public typealias SIMDType = SIMD4<Double>

	@inlinable public init(_ simdRepresentation: SIMD4<Double>) {
		self.init(center: Coordinates(simdRepresentation[0], simdRepresentation[1]), zoom: simdRepresentation[2])
	}

	@inlinable public func simdRepresentation() -> SIMD4<Double> {
		SIMD4(center.latitude, center.longitude, zoom, 0.0)
	}

	@inlinable public static func < (lhs: Camera, rhs: Camera) -> Bool {
		lhs.center.latitude < rhs.center.latitude && lhs.center.longitude < rhs.center.longitude && lhs.zoom < rhs.zoom
	}
}

