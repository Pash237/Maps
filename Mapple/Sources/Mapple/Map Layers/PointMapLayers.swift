//
//  File.swift
//  
//
//  Created by Pavel Alexeev on 11.07.2023.
//

import UIKit

open class PointMapLayer: CALayer {
	public var coordinates: Coordinates {
		didSet {
			guard oldValue != coordinates else { return }
			if let parent = superlayer?.delegate as? PointMapLayersView {
				CATransaction.begin()
				CATransaction.setDisableActions(true)
				let point = parent.projection.point(at: parent.zoom, from: coordinates)
				position = point - parent.offset
				CATransaction.commit()
			}
		}
	}
	
	public init(coordinates: Coordinates) {
		self.coordinates = coordinates
		super.init()
	}
	
	required public init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	public override init(layer: Any) {
		if let layer = layer as? Self {
			coordinates = layer.coordinates
		} else {
			coordinates = Coordinates(latitude: 0, longitude: 0)
		}
		super.init(layer: layer)
	}
	
	open var scale = 1.0
	var id: Int = 0
}

public class PointMapLayersView: UIView, MapViewLayer, TouchableMapViewLayer {
	private(set) var offset: Point = .zero
	private(set) var zoom: Double = 11
	private(set) var rotation: Radians = 0.0
	var projection = SphericalMercator()
	
	private var drawingLayersConfigs: Dictionary<Int, ((PointMapLayer?) -> (PointMapLayer))> = [:]
	private var drawingLayers: Dictionary<AnyHashable, PointMapLayer> = [:]
	private var drawnLayerOffset: CGPoint = .zero
	private var drawnLayerZoom: Double = 11
	
	override init(frame: CGRect) {
		super.init(frame: frame)
		isUserInteractionEnabled = false
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	@discardableResult
	public func addMapLayer(id: AnyHashable = UUID(), _ configureLayer: @escaping ((PointMapLayer?) -> (PointMapLayer))) -> PointMapLayer {
		//remove existent layer if it's present
		drawingLayers[id]?.removeFromSuperlayer()
		
		let drawingLayer = configureLayer(nil)
		drawingLayer.id = id.hashValue
		drawingLayersConfigs[drawingLayer.id] = configureLayer
		drawingLayers[id] = drawingLayer
		drawingLayer.scale = Self.scale(for: zoom)
		layer.addSublayer(drawingLayer)
		
		redrawLayer(id: id)
		positionDrawingLayer(drawingLayer)
		
		return drawingLayer
	}
	
	public func removeMapLayer(_ layer: PointMapLayer) {
		for (key, existent) in drawingLayers {
			if layer === existent {
				drawingLayersConfigs[layer.id] = nil
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
	
	public func mapLayer(with id: AnyHashable) -> PointMapLayer? {
		drawingLayers[id]
	}
	
	public func allLayerIds() -> [AnyHashable] {
		Array(drawingLayers.keys)
	}
	
	public func allLayers() -> [PointMapLayer] {
		Array(drawingLayers.values)
	}
	
	public func update(offset: Point, zoom: Double, rotation: Radians) {
		self.offset = offset
		self.zoom = zoom
		self.rotation = rotation
		
		if drawnLayerZoom != zoom || drawnLayerOffset.distance(to: offset) > bounds.width {
			for layer in drawingLayers.values {
				layer.scale = Self.scale(for: zoom)
			}
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
			let _ = drawingLayersConfigs[id.hashValue]?(layer)
		}
				
		CATransaction.commit()
	}
	
	public func redrawLayers(allowAnimation: Bool = false) {
		for layer in drawingLayers.values {
			let _ = drawingLayersConfigs[layer.id]?(layer)
		}
		
		drawnLayerZoom = zoom
		drawnLayerOffset = offset
	}
	
	public func layerIds(at coordinates: Coordinates, threshold: CGFloat = 30.0) -> [(key: AnyHashable, distance: CGFloat)] {
		drawingLayers.compactMap { key, layer in
			guard !layer.isHidden else { return nil }
			
			let point = projection.point(at: zoom, from: coordinates) - offset
			let distance = layer.position.distance(to: point)
			if distance < threshold {
				let pointLayersPriority = 6.0
				return (key, distance - pointLayersPriority)
			} else {
				return nil
			}
		}
	}
	
	private func positionDrawingLayer(_ layer: PointMapLayer) {
		let point = projection.point(at: zoom, from: layer.coordinates)
		layer.transform = CATransform3DMakeRotation(rotation, 0, 0, -1)
		layer.position = point - offset
	}
	
	private func positionDrawingLayers() {
		let insetBounds = bounds.insetBy(dx: -bounds.width*1.5, dy: -bounds.height*1.5)
		let visibleCoordinateBounds = CoordinateBounds(northeast: self.coordinates(at: CGPoint(insetBounds.maxX, insetBounds.minY)),
													   southwest: self.coordinates(at: CGPoint(insetBounds.minX, insetBounds.maxY)))
		
		for layer in drawingLayers.values {
			if visibleCoordinateBounds.contains(layer.coordinates) {
				positionDrawingLayer(layer)
				if layer.isHidden {
					layer.isHidden = false
				}
			} else if !layer.isHidden {
				layer.isHidden = true
			}
		}
	}
		
	private func coordinates(at screenPoint: Point) -> Coordinates {
		projection.coordinates(from: offset + screenPoint, at: zoom)
	}
	
	public static func scale(for zoom: Double) -> Double {
		min(max(1.0 - (11.0 - zoom) / (11.0 - 7.0), 0.0), 1.0)
	}
}

