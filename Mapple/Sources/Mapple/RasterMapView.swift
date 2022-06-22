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
	
	private var tileLayersCache: [String: [MapTile: MapTileLayer]] = [:]
	
	public var tileSources: [TileSource]
	
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
	
	public init(frame: CGRect, tileSources: [TileSource]) {
		self.tileSources = tileSources
		
		super.init(frame: frame)
		
		addRequiredTileLayers()
		positionTileLayers()
	}

	public convenience init(frame: CGRect, tileSource: TileSource) {
		self.init(frame: frame, tileSources: [tileSource])
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	private var tileSize: Int { tileSources[0].tileSize }
	
	private func addRequiredTileLayers() {
		let requiredZoom: Int = Int(zoom.rounded())
		let margin = CGPoint(x: 300, y: 300)
		let min = (projection.convert(point: offset, from: zoom, to: Double(requiredZoom)) - margin) / Double(tileSize)
		let max = min + (Point(x: bounds.width, y: bounds.height) + margin*2) / Double(tileSize)
		
		for tileSource in tileSources {
			for x in Int(min.x)...Int(max.x) {
				for y in Int(min.y)...Int(max.y) {
					let tile = MapTile(x: x, y: y, zoom: requiredZoom, size: tileSize)
					if tileLayersCache[tileSource.url] == nil {
						tileLayersCache[tileSource.url] = [:]
					}
					if tileLayersCache[tileSource.url]![tile] == nil {
						let layer = MapTileLayer(tile: tile, tileSource: tileSource)
						self.layer.addSublayer(layer)
						tileLayersCache[tileSource.url]![tile] = layer
					}
				}
			}
		}
	}
	
	private func remove(layer tileLayer: MapTileLayer, in tileSource: TileSource) {
		tileLayersCache[tileSource.url]?.removeValue(forKey: tileLayer.tile)
		layer.sublayers?.remove(object: tileLayer)
	}
	
	private func removeUnusedTileLayers() {
		let margin = CGPoint(x: 300, y: 300)
		let bestZoom = Int(zoom.rounded())
		
		for tileSource in tileSources {
			let tileLayers = (tileLayersCache[tileSource.url] ?? [:]).values
			for tileLayer in tileLayers {
				// if tile is out of screen (with some margin), remove it
				if !bounds.insetBy(dx: -margin.x, dy: -margin.y).intersects(tileLayer.frame) {
					remove(layer: tileLayer, in: tileSource)
					continue
				}
			}
		}
	}

	private func positionTileLayers() {
		for tileSource in tileSources {
			let tileLayers = (tileLayersCache[tileSource.url] ?? [:]).values
			let indexAcrossMapSources = tileSources.count == 1
										  ? 0
										  : tileSources.count - tileSources.firstIndex(where: {$0.url == tileSource.url })!
			
			for layer in tileLayers {
				let scale = pow(2.0, zoom - Double(layer.tile.zoom))
				let size = Double(tileSource.tileSize) * scale
				layer.frame = CGRect(
					origin: projection.convert(point: layer.tile.offset, from: Double(layer.tile.zoom), to: zoom) - offset,
					size: CGSize(width: size, height: size))
				
				layer.zPosition = -abs(zoom.rounded() - Double(layer.tile.zoom)) - 25.0 * Double(indexAcrossMapSources)
			}
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
	public func screenPoint(at coordinates: Coordinates) -> Point {
		point(at: coordinates) - offset
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
