//
//  Camera.swift
//  maps
//
//  Created by Pavel Alexeev on 09.06.2022.
//

import Foundation

public struct Camera {
	public var center: Coordinates
	public var zoom: Double
	
	public init(center: Coordinates, zoom: Double) {
		self.center = center
		self.zoom = zoom
	}
}
