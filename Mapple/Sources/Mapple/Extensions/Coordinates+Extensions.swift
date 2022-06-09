//
//  Coordinates+Extensions.swift
//  maps
//
//  Created by Pavel Alexeev on 07.06.2022.
//

import CoreLocation

public typealias Coordinates = CLLocationCoordinate2D

public func +(lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
	CLLocationCoordinate2D(latitude: lhs.latitude + rhs.latitude, longitude: lhs.longitude + rhs.longitude)
}

public func -(lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
	CLLocationCoordinate2D(latitude: lhs.latitude - rhs.latitude, longitude: lhs.longitude - rhs.longitude)
}

public extension Coordinates {
	init(_ latitude: CLLocationDegrees, _ longitude: CLLocationDegrees) {
		self.init(latitude: latitude, longitude: longitude)
	}
}

public struct CoordinateBounds {
	var northeast: Coordinates
	var southwest: Coordinates
}

public extension Array where Element == Coordinates {
	func bounds() -> CoordinateBounds {
		//TODO: Chukotka will have troubles if points contains both -179 and 179 degrees
		
		var minLatitude = Double.greatestFiniteMagnitude
		var maxLatitude = -Double.greatestFiniteMagnitude
		var minLongitude = Double.greatestFiniteMagnitude
		var maxLongitude = -Double.greatestFiniteMagnitude
		
		for coordinates in self {
			if coordinates.latitude < minLatitude {
				minLatitude = coordinates.latitude
			}
			if coordinates.latitude > maxLatitude {
				maxLatitude = coordinates.latitude
			}
			if coordinates.longitude < minLongitude {
				minLongitude = coordinates.longitude
			}
			if coordinates.longitude > maxLongitude {
				maxLongitude = coordinates.longitude
			}
		}
		
		return CoordinateBounds(northeast: Coordinates(latitude: maxLatitude, longitude: minLongitude),
								southwest: Coordinates(latitude: minLatitude, longitude: maxLongitude))
	}
}
