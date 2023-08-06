//
//  SpatialMapLayers.swift
//  
//
//  Created by Pavel Alexeev on 09.07.2023.
//

import UIKit

public class SpatialMapLayersView: UIView, MapViewLayer {
	private var offset: Point = .zero
	private var zoom: Double = 11
	private var rotation: Radians = 0.0
	var projection = SphericalMercator()
	
	private var drawingLayersConfigs: Dictionary<AnyHashable, ((CALayer?) -> (CALayer))> = [:]
	private var drawingLayers: Dictionary<AnyHashable, CALayer> = [:]
	private var drawnLayerOffset: CGPoint = .zero
	private var drawnLayerZoom: Double = 11
	private var drawingViews: Dictionary<AnyHashable, UIView> = [:]
	
	override init(frame: CGRect) {
		super.init(frame: frame)
		isUserInteractionEnabled = false
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	@discardableResult
	public func addMapLayer(id: AnyHashable = UUID(), _ configureLayer: @escaping ((CALayer?) -> (CALayer))) -> CALayer {
		//remove existent layer if it's present
		drawingLayers[id]?.removeFromSuperlayer()
		
		let drawingLayer = configureLayer(nil)
		drawingLayersConfigs[id] = configureLayer
		drawingLayers[id] = drawingLayer
		layer.addSublayer(drawingLayer)
		
		redrawLayer(id: id)
		positionDrawingLayer(drawingLayer)
		
		return drawingLayer
	}
	
	public func removeMapLayer(_ layer: CALayer) {
		for (key, existent) in drawingLayers {
			if layer === existent {
				drawingLayersConfigs[key] = nil
				drawingLayers[key] = nil
				break
			}
		}
		
		layer.removeFromSuperlayer()
	}
	
	public func removeMapLayer(_ id: AnyHashable) {
		if let layer = drawingLayers[id] {
			removeMapLayer(layer)
		}
	}
	
	public func mapLayer(with id: AnyHashable) -> CALayer? {
		drawingLayers[id]
	}
	
	public func allLayerIds() -> [AnyHashable] {
		Array(drawingLayers.keys)
	}
	
	public func update(offset: Point, zoom: Double, rotation: Radians) {
		self.offset = offset
		self.zoom = zoom
		self.rotation = rotation
		
		if drawnLayerZoom != zoom || drawnLayerOffset.distance(to: offset) > bounds.width {
			redrawLayers()
		}
		positionDrawingLayers()
	}
	
	public func redrawLayer(id: AnyHashable, allowAnimation: Bool = false) {
		CATransaction.begin()
		if !allowAnimation {
			CATransaction.setDisableActions(true)
		}
		
		if let layer = drawingLayers[id] {
			let _ = drawingLayersConfigs[id]?(layer)
		}
				
		CATransaction.commit()
	}
	
	func redrawLayers(allowAnimation: Bool = false) {
		for (key, layer) in drawingLayers {
			let _ = drawingLayersConfigs[key]?(layer)
		}
		
		drawnLayerZoom = zoom
		drawnLayerOffset = offset
	}
	
	func layerIds(at coordinates: Coordinates, threshold: CGFloat = 30.0) -> [(key: AnyHashable, distance: CGFloat)] {
		drawingLayers.compactMap { key, layer in
			let point = projection.point(at: zoom, from: coordinates)
			if let distance = layer.distance(to: point), distance < threshold {
				return (key, distance)
			} else {
				return nil
			}
		}
	}
	
	private func positionDrawingLayer(_ layer: CALayer) {
		layer.position = .zero - offset //projection.convert(point: drawnLayerOffset, from: Double(drawnLayerZoom), to: zoom) - offset
		let scale = pow(2.0, zoom - Double(drawnLayerZoom))
		layer.transform = CATransform3DMakeScale(scale, scale, 1)
	}
	
	private func positionDrawingLayers() {
		drawingLayers.values.forEach(positionDrawingLayer)
	}
}


extension SpatialMapLayersView {
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
				let point = projection.point(at: zoom, from: coordinates)
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
				let endPoint = projection.point(at: zoom, from: lastCoordinates)
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
	
	private func coordinates(at screenPoint: Point) -> Coordinates {
		projection.coordinates(from: offset + screenPoint, at: zoom)
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
