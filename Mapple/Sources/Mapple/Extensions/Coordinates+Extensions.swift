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

public func +=(lhs: inout CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) {
	lhs = lhs + rhs
}

public func -=(lhs: inout CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) {
	lhs = lhs - rhs
}

extension Coordinates: Hashable {
	public init(_ latitude: CLLocationDegrees, _ longitude: CLLocationDegrees) {
		self.init(latitude: latitude, longitude: longitude)
	}
	
	
	public static func ==(lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
		lhs.longitude == rhs.longitude && lhs.latitude == rhs.latitude
	}
	
	public func hash(into hasher: inout Hasher) {
		hasher.combine(latitude)
		hasher.combine(longitude)
	}
	
	func isNearlyEqual(to coordinates: Self, precision: CLLocationDegrees = 0.0000001) -> Bool {
		latitude.isNearlyEqual(to: coordinates.latitude, precision: precision)
		&&
		longitude.isNearlyEqual(to: coordinates.longitude, precision: precision)
	}
}

public struct CoordinateBounds: Codable, Hashable, Equatable, CustomStringConvertible {
	var northeast: Coordinates
	var southwest: Coordinates
	
	public init(northeast: Coordinates, southwest: Coordinates) {
		self.northeast = northeast
		self.southwest = southwest
	}
	
	public init(northwest: Coordinates, southeast: Coordinates) {
		self.northeast = Coordinates(max(northwest.latitude, southeast.latitude), max(northwest.longitude, southeast.longitude))
		self.southwest = Coordinates(min(northwest.latitude, southeast.latitude), min(northwest.longitude, southeast.longitude))
	}
	
	public init(coordinates: [Coordinates]) {
		//TODO: Chukotka will have troubles if points contains both -179 and 179 degrees
		
		guard !coordinates.isEmpty else {
			self.init(northeast: Coordinates(85, 179), southwest: Coordinates(-85, -179))
			return
		}
		
		var minLatitude = Double.greatestFiniteMagnitude
		var maxLatitude = -Double.greatestFiniteMagnitude
		var minLongitude = Double.greatestFiniteMagnitude
		var maxLongitude = -Double.greatestFiniteMagnitude
		
		for coordinate in coordinates {
			if coordinate.latitude < minLatitude {
				minLatitude = coordinate.latitude
			}
			if coordinate.latitude > maxLatitude {
				maxLatitude = coordinate.latitude
			}
			if coordinate.longitude < minLongitude {
				minLongitude = coordinate.longitude
			}
			if coordinate.longitude > maxLongitude {
				maxLongitude = coordinate.longitude
			}
		}
		
		self.init(northeast: Coordinates(latitude: maxLatitude, longitude: maxLongitude),
				  southwest: Coordinates(latitude: minLatitude, longitude: minLongitude))
	}
	
	public var northwest: Coordinates {
		Coordinates(northeast.latitude, southwest.longitude)
	}
	
	public var southeast: Coordinates {
		Coordinates(southwest.latitude, northeast.longitude)
	}
	
	public func contains(_ coordinates: Coordinates) -> Bool {
		let latitude = coordinates.latitude
		let longitude = coordinates.longitude.remainder(dividingBy: 360.0)
		
		return latitude > min(northeast.latitude, southwest.latitude) && latitude < max(northeast.latitude, southwest.latitude)
			   &&
			   longitude > min(northeast.longitude, southwest.longitude) && longitude < max(northeast.longitude, southwest.longitude)
	}
	
	public func intersects(with other: CoordinateBounds) -> Bool {
		northeast.latitude > other.southwest.latitude
			&& southwest.latitude < other.northeast.latitude
		    && northeast.longitude > other.southwest.longitude
			&& southwest.longitude < other.northeast.longitude
	}
		
	public var description: String {
		"(\(southwest.latitude), \(southwest.longitude)) — (\(northeast.latitude), \(northeast.longitude))"
	}
	
	public var center: Coordinates {
		Coordinates(
			(northeast.latitude + southwest.latitude)/2,
			(northeast.longitude + southwest.longitude)/2
		)
	}
}

}

public extension Array where Element == Coordinates {
	func centroid() -> Coordinates {
		guard !isEmpty else {
			return Coordinates(0, 0)
		}
		
		return Coordinates(
			(map {$0.latitude}.reduce(0, +))/Double(count),
			(map {$0.longitude}.reduce(0, +))/Double(count)
		)
	}
}


extension FloatingPoint {
	func isNearlyEqual(to value: Self, precision: Self = .ulpOfOne) -> Bool {
		abs(self - value) <= precision
	}
}
