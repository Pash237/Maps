//
//  NumberExtensions.swift
//
//
//  Created by Pavel Alexeev on 24.04.2024.
//

import Foundation

extension Comparable {
	func clamped(to limits: ClosedRange<Self>) -> Self {
		return min(max(self, limits.lowerBound), limits.upperBound)
	}
}
