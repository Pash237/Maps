//
//  Array+Extensions.swift
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
