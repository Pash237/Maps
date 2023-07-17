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
			if let parent = superlayer?.delegate as? PointMapLayersView {
				let point = parent.projection.point(at: parent.zoom, from: coordinates)
				position = point - parent.offset
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
}

public class PointMapLayersView: UIView {
	private(set) var offset: Point = .zero
	private(set) var zoom: Double = 11
	private(set) var rotation: Radians = 0.0
	var projection = SphericalMercator()
	
	private var drawingLayersConfigs: Dictionary<AnyHashable, ((PointMapLayer?) -> (PointMapLayer))> = [:]
	private var drawingLayers: Dictionary<AnyHashable, PointMapLayer> = [:]
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
	public func addMapLayer(id: AnyHashable = UUID(), _ configureLayer: @escaping ((PointMapLayer?) -> (PointMapLayer))) -> PointMapLayer {
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
	
	public func removeMapLayer(_ layer: PointMapLayer) {
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
	
	public func mapLayer(with id: AnyHashable) -> PointMapLayer? {
		drawingLayers[id]
	}
	
	public func allLayerIds() -> [AnyHashable] {
		Array(drawingLayers.keys)
	}
	
	func update(offset: Point, zoom: Double, rotation: Radians) {
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
	
	public func redrawLayers(allowAnimation: Bool = false) {
		for (key, layer) in drawingLayers {
			let _ = drawingLayersConfigs[key]?(layer)
		}
		
		drawnLayerZoom = zoom
		drawnLayerOffset = offset
	}
	
	func layerIds(at coordinates: Coordinates, threshold: CGFloat = 30.0) -> [(key: AnyHashable, distance: CGFloat)] {
		drawingLayers.compactMap { key, layer in
			let point = projection.point(at: zoom, from: coordinates) - offset
			let distance = layer.position.distance(to: point)
			if distance < threshold {
				return (key, distance)
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
		drawingLayers.values.forEach(positionDrawingLayer)
	}
	
}
