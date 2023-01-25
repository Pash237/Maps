//
//  File.swift
//  
//
//  Created by Pavel Alexeev on 03.01.2023.
//

import UIKit

extension MapView {
	@discardableResult
	public func addLineLayer(id: AnyHashable = UUID(), _ coordinates: [Coordinates], width: CGFloat = 4, strokeWidth: CGFloat = 1, color: CGColor, strokeColor: CGColor) -> CALayer {
		addLineLayer(id: id, {coordinates}, width: width, strokeWidth: strokeWidth, color: color, strokeColor: strokeColor)
	}
	
	@discardableResult
	public func addLineLayer(id: AnyHashable = UUID(), _ coordinates: @escaping () -> ([Coordinates]), width: CGFloat = 4, strokeWidth: CGFloat = 1, color: CGColor, strokeColor: CGColor) -> CALayer {
		addMapLayer(id: id, {[unowned self] layer in
			let layer = layer ?? CALayer()
			if layer.sublayers?.count ?? 0 < 2 {
				layer.addSublayer(CAShapeLayer())
				layer.addSublayer(CAShapeLayer())
			}
			let main = layer.sublayers![1] as! CAShapeLayer
			let outline = layer.sublayers![0] as! CAShapeLayer
			
			let linePath = UIBezierPath()
			
			let coordinates = coordinates()
			
			let insetBounds = bounds.insetBy(dx: -bounds.width*1.5, dy: -bounds.height*1.5)
			
			var lastPoint: Point = .zero
			for i in stride(from: 0, to: coordinates.count, by: max(1, 15 - Int(round(zoom)))) {
				let coordinates = coordinates[i]
				let point = point(at: coordinates)
				guard insetBounds.contains(point-offset) else {
					lastPoint = .zero
					continue
				}
				if lastPoint == .zero {
					linePath.move(to: point)
					lastPoint = point
				} else if (lastPoint - point).maxDimension > 1 {
					linePath.addLine(to: point)
					lastPoint = point
				}
			}
			// always add last point as it may by thrown away by stride
			if let lastCoordinates = coordinates.last {
				let endPoint = point(at: lastCoordinates)
				if (lastPoint - endPoint).maxDimension > 1 && insetBounds.contains(endPoint-offset) {
					linePath.addLine(to: endPoint)
				}
			}
			
			main.path = linePath.cgPath
			main.opacity = 1
			main.lineWidth = width
			main.lineCap = .round
			main.lineJoin = .round
			main.fillColor = UIColor.clear.cgColor
			main.strokeColor = color
			
			if strokeWidth > 0 {
				outline.path = linePath.cgPath
				outline.opacity = 1
				outline.lineWidth = width + strokeWidth*2
				outline.lineCap = .round
				outline.lineJoin = .round
				outline.fillColor = UIColor.clear.cgColor
				outline.strokeColor = strokeColor
				outline.isHidden = false
			} else {
				outline.isHidden = true
			}
			
			return layer
		})
	}
	
	@discardableResult
	public func updateLineLayer(id: AnyHashable = UUID(), _ coordinates: [Coordinates], width: CGFloat = 4, strokeWidth: CGFloat = 1, color: CGColor, strokeColor: CGColor) -> CALayer {
		addLineLayer(id: id, {coordinates}, width: width, strokeWidth: strokeWidth, color: color, strokeColor: strokeColor)
	}
}


extension CALayer {
	func shapeContains(_ checkPoint: CGPoint, distance: CGFloat = 30) -> Bool {
		if let path = (self as? CAShapeLayer)?.path {
			
			//TODO: linear-interpolate line, becase it might have points which are far from each other
			
			for point in path.getPoints() {
				if point.distance(to: checkPoint) < distance {
					return true
				}
			}
		}
		for sublayer in sublayers ?? [] {
			if sublayer.shapeContains(checkPoint, distance: distance) {
				return true
			}
		}
		
		return false
	}
}
