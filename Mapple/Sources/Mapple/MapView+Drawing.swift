//
//  MapView+Drawing.swift
//  
//
//  Created by Pavel Alexeev on 03.01.2023.
//

import UIKit
import CoreLocation

extension MapView {
	@discardableResult
	public func addLineLayer(id: AnyHashable = UUID(), _ coordinates: @autoclosure @escaping () -> ([Coordinates]), width: CGFloat = 4, strokeWidth: CGFloat = 1, color: CGColor, strokeColor: CGColor = CGColor(gray: 1, alpha: 1)) -> CALayer {
		addLineLayer(id: id, coordinates, width: width, strokeWidth: strokeWidth, color: color, strokeColor: strokeColor)
	}
	
	@discardableResult
	public func addLineLayer(id: AnyHashable = UUID(), _ coordinates: @escaping () -> ([Coordinates]), width: CGFloat = 4, strokeWidth: CGFloat = 1, color: CGColor, strokeColor: CGColor = CGColor(gray: 1, alpha: 1)) -> CALayer {
		
		let layerCoordinateBounds = CoordinateBounds(coordinates: coordinates())
		var forceSetupLayers = true
		
		return addMapLayer(id: id, {[unowned self] layer in
			let layer = layer ?? CALayer()
			
			let insetBounds = bounds.insetBy(dx: -bounds.width*1.5, dy: -bounds.height*1.5)
			let visibleCoordinateBounds = CoordinateBounds(northeast: self.coordinates(at: CGPoint(insetBounds.width, 0)),
														   southwest: self.coordinates(at: CGPoint(0, insetBounds.height)))
			
			guard visibleCoordinateBounds.intersects(with: layerCoordinateBounds) else {
				return layer
			}
			
			var needToSetUpLayers = forceSetupLayers
			if layer.sublayers?.count ?? 0 < 2 {
				layer.addSublayer(CAShapeLayer())
				layer.addSublayer(CAShapeLayer())
				needToSetUpLayers = true
				forceSetupLayers = false
			}
			let main = layer.sublayers![1] as! CAShapeLayer
			let outline = layer.sublayers![0] as! CAShapeLayer
			
			let linePath = UIBezierPath()
			
			let coordinates = coordinates()
			
			let pointToSkip = max(0, 17 - Int(round(zoom)))
			let minimumPointDistance = zoom > 18 ? 1.0 : (zoom > 14 ? 3.0 : 4.0)
			
			var lastPoint: Point = .zero
			var i = 0
			while i < coordinates.count {
				let coordinates = coordinates[i]
				let point = point(at: coordinates)
				guard insetBounds.contains(point-offset) else {
					lastPoint = .zero
					i += 20 + pointToSkip
					continue
				}
				if lastPoint == .zero {
					linePath.move(to: point)
					lastPoint = point
				} else if (lastPoint - point).maxDimension > minimumPointDistance {
					linePath.addLine(to: point)
					lastPoint = point
				}
				
				i += 1 + pointToSkip
			}
			// always add last point as it may by thrown away by stride
			if let lastCoordinates = coordinates.last {
				let endPoint = point(at: lastCoordinates)
				if (lastPoint - endPoint).maxDimension > 1 && insetBounds.contains(endPoint-offset) {
					linePath.addLine(to: endPoint)
				}
			}
			
			main.path = linePath.cgPath
			if needToSetUpLayers {
				main.opacity = 1
				main.lineWidth = width
				main.lineCap = .round
				main.lineJoin = .round
				main.fillColor = UIColor.clear.cgColor
				main.strokeColor = color
			}
			
			if strokeWidth > 0 {
				outline.path = linePath.cgPath
				if needToSetUpLayers {
					outline.opacity = 1
					outline.lineWidth = width + strokeWidth*2
					outline.lineCap = .round
					outline.lineJoin = .round
					outline.fillColor = UIColor.clear.cgColor
					outline.strokeColor = strokeColor
				}
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
	
	public func updateLineLayer(id: AnyHashable = UUID(), width: CGFloat = 4, strokeWidth: CGFloat = 1, color: CGColor, strokeColor: CGColor) {
		guard let layer = mapLayer(with: id),
			  layer.sublayers?.count ?? 0 >= 2 else {
			return
		}
		let main = layer.sublayers![1] as! CAShapeLayer
		let outline = layer.sublayers![0] as! CAShapeLayer
		
		main.lineWidth = width
		main.strokeColor = color
		
		if strokeWidth > 0 {
			outline.lineWidth = width + strokeWidth*2
			outline.strokeColor = strokeColor
			if outline.isHidden != false {
				outline.isHidden = false
			}
		} else if outline.isHidden != true {
			outline.isHidden = true
		}
	}
}

extension MapView {
	private static let screenScale = UIScreen.main.scale
	
	@discardableResult
	public func addImageLayer(id: AnyHashable = UUID(), _ coordinates: @escaping () -> (Coordinates), image: CGImage) -> CALayer {

		return addMapLayer(id: id, {[unowned self] layer in
			let layer = layer ?? CALayer()
			if layer.sublayers == nil {
				layer.addSublayer(CALayer())
			}
			let imageLayer = layer.sublayers!.first!
			
			let insetBounds = bounds.insetBy(dx: -bounds.width*1.5, dy: -bounds.height*1.5)
			let visibleCoordinateBounds = CoordinateBounds(northeast: self.coordinates(at: CGPoint(insetBounds.width, 0)),
														   southwest: self.coordinates(at: CGPoint(0, insetBounds.height)))
			let coordinates = coordinates()
			
			guard visibleCoordinateBounds.contains(coordinates) else {
				return layer
			}
			
			imageLayer.bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width)/Self.screenScale, height: CGFloat(image.height)/Self.screenScale)
			imageLayer.contents = image
			imageLayer.position = point(at: coordinates)
			
			return layer
		})
	}
}


extension CALayer {
	func distance(to checkPoint: CGPoint, threshold: CGFloat = 30, lowThreshold: CGFloat = 10) -> CGFloat? {
		if let path = (self as? CAShapeLayer)?.path {
			
			//TODO: linear-interpolate line, becase it might have points which are far from each other
			
			var minDistance: CGFloat?
			var threshold = threshold
			for point in path.getPoints() {
				let distance = point.distance(to: checkPoint)
				if distance < threshold {
					minDistance = distance
					threshold = distance
					if distance < lowThreshold {
						break
					}
				}
			}
			return minDistance
		}
		if contents != nil {
			if frame.contains(checkPoint) {
				return frame.center.distance(to: checkPoint)
			} else {
				return nil
			}
		}
		for sublayer in sublayers ?? [] {
			if let distance = sublayer.distance(to: checkPoint, threshold: threshold) {
				return distance
			}
		}
		
		return nil
	}
}
