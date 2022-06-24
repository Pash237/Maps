//
//  MapView.swift
//  maps
//
//  Created by Pavel Alexeev on 01.06.2022.
//

import UIKit
import Combine
import CoreLocation

public class RasterMapView: MapScrollView {
	private let projection = SphericalMercator()
	
	private var tileLayersCache: [String: [MapTile: MapTileLayer]] = [:]
	
	public var tileSources: [TileSource]
	
	private var drawingLayersConfigs: [((CALayer?) -> (CALayer))] = []
	private var drawingLayers: [CALayer] = []
	private var drawedLayerOffset: CGPoint = .zero
	private var drawedLayerZoom: Double = 11
	
	private var bag = Set<AnyCancellable>()
	
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

		NotificationCenter.default.publisher(for: .mapTileLoaded)
			.throttle(for: 0.0, scheduler: DispatchQueue.main, latest: true)
			.sink() {[weak self] _ in
				self?.removeUnusedTileLayers()
			}
			.store(in: &bag)
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
		let requiredScale = pow(2.0, Double(requiredZoom) - zoom)
		let size = Double(tileSize)
		let margin = CGPoint(x: 300, y: 300)
		let topLeft = projection.convert(point: offset - margin, from: zoom, to: Double(requiredZoom))
		
		let min = topLeft / size
		let max = (topLeft + Point(x: bounds.width, y: bounds.height)*requiredScale + margin*2*requiredScale) / size
		
		
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
		let margin = CGPoint(x: 302, y: 302)
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

		for tileSource in tileSources {
			let tileLayers = (tileLayersCache[tileSource.url] ?? [:]).values
							  .sorted {
								  abs($0.tile.zoom - bestZoom) > abs($1.tile.zoom - bestZoom)
							  }
			for tileLayer in tileLayers {

				if tileLayer.tile.zoom != bestZoom {
					// we're zooming out and can throw away unused smaller tiles
					let loadedLargerTiles = tileLayers.filter {
						$0 !== tileLayer && $0.isLoaded && $0.tile.zoom < tileLayer.tile.zoom
					}
					if loadedLargerTiles.contains(where: {$0.frame.contains(tileLayer.frame.insetBy(dx: 1, dy: 1))}) {
						// some existing larger and more appropriate tile overlaps this tile — remove it
						remove(layer: tileLayer, in: tileSource)
						continue
					}
				}
			}
		}

		//TODO: mask larger tiles to avoid overlaps
		for tileSource in tileSources {
			let tileLayers = (tileLayersCache[tileSource.url] ?? [:]).values
							  .sorted {
								  abs($0.tile.zoom - bestZoom) > abs($1.tile.zoom - bestZoom)
							  }
			for tileLayer in tileLayers {
				if tileLayer.tile.zoom != bestZoom {
					let tileVisiblePart = tileLayer.frame.intersection(bounds)

					// don't bother with tiles that are almost offscreen
					if tileVisiblePart.width < 10 || tileVisiblePart.height < 10 {
						remove(layer: tileLayer, in: tileSource)
						continue
					}

					var isSafeToRemove = true

					// we're zooming in — delete larger tile when the area is fully covered with loaded smaller tiles
					let loadedSmallerTiles = tileLayers.filter {
						$0 !== tileLayer && $0.isLoaded && $0.tile.zoom > tileLayer.tile.zoom
					}

					// take 4 points in the visible area — if they are covered with something, suppose that entire region
					// is covered and it is safe to remove tile
					let checkPoints = [
						tileVisiblePart.origin + Point(x: tileVisiblePart.width*0.25, y: tileVisiblePart.width*0.25),
						tileVisiblePart.origin + Point(x: tileVisiblePart.width*0.75, y: tileVisiblePart.width*0.25),
						tileVisiblePart.origin + Point(x: tileVisiblePart.width*0.25, y: tileVisiblePart.width*0.75),
						tileVisiblePart.origin + Point(x: tileVisiblePart.width*0.75, y: tileVisiblePart.width*0.75),
					]
					for checkPoint in checkPoints {
						var pointCovered = false
						for layer in loadedSmallerTiles {
							if layer.frame.contains(checkPoint) {
								pointCovered = true
								break
							}
						}
						if !pointCovered {
							isSafeToRemove = false
							break
						}
					}

					if isSafeToRemove {
						// smaller more appropriate tiles are fully covering this area
						remove(layer: tileLayer, in: tileSource)
						continue
					}
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
		
		addRequiredTileLayers()
		positionTileLayers()
		removeUnusedTileLayers()
		
		if drawedLayerZoom != zoom {
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
