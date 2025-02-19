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

public func *(lhs: CLLocationCoordinate2D, rhs: Double) -> CLLocationCoordinate2D {
	CLLocationCoordinate2D(latitude: lhs.latitude * rhs, longitude: lhs.longitude * rhs)
}

extension CLLocationCoordinate2D: @retroactive Equatable {
	public static func ==(lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
		lhs.longitude == rhs.longitude && lhs.latitude == rhs.latitude
	}
}

extension Coordinates: @retroactive Hashable {
	public init(_ latitude: CLLocationDegrees, _ longitude: CLLocationDegrees) {
		self.init(latitude: latitude, longitude: longitude)
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
	var northeast: Coordinates	// (max, max) top-right
	var southwest: Coordinates	// (min, min) bottom-left
	
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
	
	public var minLatitude: Double { min(northeast.latitude, southwest.latitude) }
	public var maxLatitude: Double { max(northeast.latitude, southwest.latitude) }
	public var minLongitude: Double { min(northeast.longitude, southwest.longitude) }
	public var maxLongitude: Double { max(northeast.longitude, southwest.longitude) }
	
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
	
	/**
	 * Creates smaller approximate bounds if input meters are negative and larger bounds if meters are positive
	 */
	public func enlarge(by meters: CLLocationDistance) -> CoordinateBounds {
		let inset = Coordinates(meters / 111320,
								meters / (40075000 * cos(northeast.latitude) / 360))
		return CoordinateBounds.init(
			northeast: Coordinates(northeast.latitude + inset.latitude, northeast.longitude + inset.latitude),
			southwest: Coordinates(southwest.latitude - inset.latitude, southwest.longitude - inset.latitude)
		)
	}
}

extension CLLocationCoordinate2D: Codable {
	enum CodingKeys: CodingKey {
		case latitude
		case longitude
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(latitude, forKey: .latitude)
		try container.encode(longitude, forKey: .longitude)
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let latitude = try container.decode(CLLocationDegrees.self, forKey: .latitude)
		let longitude = try container.decode(CLLocationDegrees.self, forKey: .longitude)

		self.init(latitude: latitude, longitude: longitude)
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
	
	func bounds() -> CoordinateBounds {
		CoordinateBounds(coordinates: self)
	}
}


public extension FloatingPoint {
	func isNearlyEqual(to value: Self, precision: Self = .ulpOfOne) -> Bool {
		abs(self - value) <= precision
	}
}
