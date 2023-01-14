//
//  File.swift
//  
//
//  Created by Pavel Alexeev on 03.01.2023.
//

import UIKit

extension MapView {
	@discardableResult
	public func addLineLayer(id: AnyHashable = UUID(), _ coordinates: [Coordinates], width: CGFloat = 4, color: CGColor = UIColor.systemRed.cgColor) -> CALayer {
		addLineLayer(id: id, {coordinates}, width: width, color: color)
	}
	
	@discardableResult
	public func addLineLayer(id: AnyHashable = UUID(), _ coordinates: [Coordinates], width: CGFloat = 4, strokeWidth: CGFloat = 1, color: CGColor, strokeColor: CGColor) -> CALayer {
		addLineLayer(id: id, {coordinates}, width: width, strokeWidth: strokeWidth, color: color, strokeColor: strokeColor)
	}
	
	@discardableResult
	public func addLineLayer(id: AnyHashable = UUID(), _ coordinates: @escaping () -> ([Coordinates]), width: CGFloat = 4, color: CGColor = UIColor.systemRed.cgColor) -> CALayer {
		addMapLayer(id: id, {[unowned self] layer in
			let layer = layer as? CAShapeLayer ?? CAShapeLayer()
			let linePath = UIBezierPath()
			
			let coordinates = coordinates()
			
			var lastPoint: Point = .zero
			for i in stride(from: 0, to: coordinates.count, by: max(1, 15 - Int(zoom))) {
				let coordinates = coordinates[i]
				let point = point(at: coordinates)
				if i == 0 {
					linePath.move(to: point)
				} else if (lastPoint - point).maxDimension > 1 {
					linePath.addLine(to: point)
					
					lastPoint = point
				}
			}
			
			layer.path = linePath.cgPath
			layer.opacity = 1
			layer.lineWidth = width
			layer.lineCap = .round
			layer.lineJoin = .round
			layer.fillColor = UIColor.clear.cgColor
			layer.strokeColor = color
			
			return layer
		})
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
			
			var lastPoint: Point = .zero
			for i in stride(from: 0, to: coordinates.count, by: max(1, 15 - Int(zoom))) {
				let coordinates = coordinates[i]
				let point = point(at: coordinates)
				if i == 0 {
					linePath.move(to: point)
				} else if (lastPoint - point).maxDimension > 1 {
					linePath.addLine(to: point)
					
					lastPoint = point
				}
			}
			
			main.path = linePath.cgPath
			main.opacity = 1
			main.lineWidth = width
			main.lineCap = .round
			main.lineJoin = .round
			main.fillColor = UIColor.clear.cgColor
			main.strokeColor = color
			
			outline.path = linePath.cgPath
			outline.opacity = 1
			outline.lineWidth = width + strokeWidth*2
			outline.lineCap = .round
			outline.lineJoin = .round
			outline.fillColor = UIColor.clear.cgColor
			outline.strokeColor = strokeColor
			
			return layer
		})
	}
}
