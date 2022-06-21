//
//  MapView.swift
//  maps
//
//  Created by Pavel Alexeev on 01.06.2022.
//

import UIKit
import CoreLocation

public class RasterMapView: MapScrollView {
	private let projection = SphericalMercator()
	
	private var tileLayersCache: [MapTile: MapTileLayer] = [:]
	
	public var tileSource: TileSource
	
	private var drawingLayersConfigs: [((CALayer?) -> (CALayer))] = []
	private var drawingLayers: [CALayer] = []
	private var drawedLayerOffset: CGPoint = .zero
	private var drawedLayerZoom: Double = 11
	
	public var camera: Camera {
		get {
			Camera(center: coordinates(at: offset + bounds.center), zoom: zoom)
		}
		set {
			zoom = newValue.zoom
			offset = point(at: newValue.center) - bounds.center
			didScroll()
		}
	}

	public init(frame: CGRect, tileSource: TileSource) {
		self.tileSource = tileSource
		
		super.init(frame: frame)
		
		addRequiredTileLayers()
		positionTileLayers()
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	private var tileSize: Int { tileSource.tileSize }
	
	private func addRequiredTileLayers() {
		let requiredZoom: Int = Int(zoom.rounded())
		let margin = CGPoint(x: 300, y: 300)
		let min = (projection.convert(point: offset, from: zoom, to: Double(requiredZoom)) - margin) / Double(tileSize)
		let max = min + (Point(x: bounds.width, y: bounds.height) + margin*2) / Double(tileSize)
		
		for x in Int(min.x)...Int(max.x) {
			for y in Int(min.y)...Int(max.y) {
				let tile = MapTile(x: x, y: y, zoom: requiredZoom, size: tileSize)
				if tileLayersCache[tile] == nil {
					let layer = MapTileLayer(tile: tile, tileSource: tileSource)
					self.layer.addSublayer(layer)
					tileLayersCache[tile] = layer
				}
			}
		}
	}
	
	private var tileLayers: [MapTileLayer] {
		(layer.sublayers ?? []).compactMap {$0 as? MapTileLayer}
	}
	
	private func removeUnusedTileLayers() {
		//TODO: remove layers
		
		let margin = CGPoint(x: 300, y: 300)
		
		for tileLayer in tileLayers {
			if tileLayer.tile.zoom != Int(zoom.rounded()) {
//				layer.sublayers?.remove(object: tileLayer)
			}
			
			let tileRectOnScreen = convert(tileLayer.frame, to: self).insetBy(dx: -margin.x, dy: -margin.y)
			
			if !bounds.intersects(tileRectOnScreen) {
				tileLayersCache[tileLayer.tile] = nil
				layer.sublayers?.remove(object: tileLayer)
			}
		}
	}

	private func positionTileLayers() {
		for layer in tileLayers {
			layer.position = projection.convert(point: layer.tile.offset, from: Double(layer.tile.zoom), to: zoom) - offset
			let scale = pow(2.0, zoom - Double(layer.tile.zoom))
			layer.transform = CATransform3DMakeScale(scale, scale, 1)
			
			layer.zPosition = -abs(zoom.rounded() - Double(layer.tile.zoom))
		}
	}
	
	private func positionDrawingLayers() {
		for layer in drawingLayers {
			layer.position = projection.convert(point: drawedLayerOffset, from: Double(drawedLayerZoom), to: zoom) - offset
			let scale = pow(2.0, zoom - Double(drawedLayerZoom))
			layer.transform = CATransform3DMakeScale(scale, scale, 1)
			layer.zPosition = 1
		}
	}

	public func coordinates(at screenPoint: Point) -> Coordinates {
		projection.coordinates(from: screenPoint, at: zoom, tileSize: tileSize)
	}
	
	public func point(at coordinates: Coordinates) -> Point {
		projection.point(at: zoom, tileSize: tileSize, from: coordinates)
	}
	
	public override func didScroll() {
		CATransaction.setDisableActions(true)
		
		//TODO: use combine
		DispatchQueue.main.asyncThrottle(target: self, minimumDelay: 0.1) {[self] in
			removeUnusedTileLayers()
		}
		DispatchQueue.main.asyncDebounce(target: self, after: 0.1) {[self] in
			removeUnusedTileLayers()
			
			if ProcessInfo.processInfo.isLowPowerModeEnabled && drawedLayerZoom != zoom {
				CATransaction.setDisableActions(true)
				redrawLayers()
				positionDrawingLayers()
				CATransaction.setDisableActions(false)
			}
		}
		
		addRequiredTileLayers()
		positionTileLayers()
		
		if drawedLayerZoom != zoom && !ProcessInfo.processInfo.isLowPowerModeEnabled {
			redrawLayers()
		}
		positionDrawingLayers()
		
		CATransaction.setDisableActions(false)
	}
	
	@discardableResult
	public func addMapLayer(_ configureLayer: @escaping ((CALayer?) -> (CALayer))) -> CALayer {
		let drawingLayer = configureLayer(nil)
		drawingLayersConfigs.append(configureLayer)
		drawingLayers.append(drawingLayer)
		layer.addSublayer(drawingLayer)
		redrawLayers()
		positionDrawingLayers()
		return drawingLayer
	}
	
	private func redrawLayers() {
		for (i, layer) in drawingLayers.enumerated() {
			let _ = drawingLayersConfigs[i](layer)
		}
		
		drawedLayerZoom = zoom
	}
}
