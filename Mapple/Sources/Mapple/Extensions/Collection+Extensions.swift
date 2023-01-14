//
//  Collection+Extensions.swift
//  maps
//
//  Created by Pavel Alexeev on 03.06.2022.
//

import Foundation

extension Array where Element: Equatable {
	@discardableResult mutating func remove(object: Element) -> Bool {
		if let index = firstIndex(of: object) {
			remove(at: index)
			return true
		}
		return false
	}
}

extension Dictionary where Value: Equatable {
	@discardableResult mutating func remove(object: Value) -> Bool {
		if let key = values.firstIndex(of: object) {
			remove(at: key)
			return true
		}
		return false
	}
}
