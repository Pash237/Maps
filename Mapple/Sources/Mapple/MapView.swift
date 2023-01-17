//
//  MapView.swift
//  maps
//
//  Created by Pavel Alexeev on 01.06.2022.
//

import UIKit
import Combine
import CoreLocation
import Nuke
import Motion

public enum ScrollReason {
	case drag
	case animation
	case cameraUpdate
	case layoutChange
}

public class MapView: MapScrollView {
	private var tileLayersCache: [TileSource: [MapTile: MapTileLayer]] = [:]
	
	public var tileSources: [TileSource] {
		didSet {
			removeLayersFromUnusedTileSources()
			updateLayers()
		}
	}
	
	private var drawingLayersConfigs: Dictionary<AnyHashable, ((CALayer?) -> (CALayer))> = [:]
	private var drawingLayers: Dictionary<AnyHashable, CALayer> = [:]
	private var drawnLayerOffset: CGPoint = .zero
	private var drawnLayerZoom: Double = 11
	
	private var bag = Set<AnyCancellable>()
	
	public var onScroll = PassthroughSubject<ScrollReason, Never>()
	public var onTap = PassthroughSubject<Coordinates, Never>()
	public var onLongPress = PassthroughSubject<Coordinates, Never>()
	
	public init(frame: CGRect, tileSources: [TileSource], camera: Camera) {
		self.tileSources = tileSources
		
		super.init(frame: frame, camera: camera)
		
		NotificationCenter.default.publisher(for: .mapTileLoaded)
			.throttle(for: 0.005, scheduler: DispatchQueue.main, latest: true)
			.sink() {[weak self] _ in
				self?.removeUnusedTileLayers()
			}
			.store(in: &bag)
		
		addGestureRecognizer(TapGestureRecognizer() {[weak self] recognizer in
			guard let self = self else { return }
			let point = recognizer.location(in: self)
			let coordinates = self.coordinates(at: point)
			self.onTap.send(coordinates)
		})
		
		addGestureRecognizer(LongPressGestureRecognizer() {[weak self] recognizer in
			guard let self = self else { return }
			let point = recognizer.location(in: self)
			let coordinates = self.coordinates(at: point)
			self.onLongPress.send(coordinates)
		})
	}

	public convenience init(frame: CGRect, tileSource: TileSource, camera: Camera) {
		self.init(frame: frame, tileSources: [tileSource], camera: camera)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	private var tileSize: Int { tileSources[0].tileSize }
	
	private func addRequiredTileLayers() {
		let requiredZoom: Int = max(1, Int(zoom.rounded()))
		let requiredScale = pow(2.0, Double(requiredZoom) - zoom)
		let size = Double(tileSize)
		let margin = CGPoint(x: 200, y: 200)
		let topLeft = projection.convert(point: offset - margin, from: zoom, to: Double(requiredZoom))
		
		let min = topLeft / size
		let max = (topLeft + Point(x: bounds.width, y: bounds.height)*requiredScale + margin*2*requiredScale) / size
		
		for tileSource in tileSources {
			if tileLayersCache[tileSource] == nil {
				tileLayersCache[tileSource] = [:]
			}
		}
		
		for tileSource in tileSources {
			for x in Int(min.x)...Int(max.x) {
				for y in Int(min.y)...Int(max.y) {
					guard requiredZoom >= 0, x >= 0, y >= 0 else {
						continue
					}
					let tile = MapTile(x: x, y: y, zoom: requiredZoom, size: tileSize)
					
					if tileLayersCache[tileSource]![tile] == nil {
						let layer = MapTileLayer(tile: tile, tileSource: tileSource)
						self.layer.addSublayer(layer)
						tileLayersCache[tileSource]![tile] = layer
					}
					
					if !tileSource.hasCachedImage(for: tile) {
						//add already loaded larger tiles while this required tile is loading
						var multiplier = 1
						for smallerZoom in (1..<requiredZoom).reversed() {
							multiplier *= 2
							let largerTile = MapTile(x: tile.x/multiplier,
													 y: tile.y/multiplier,
													 zoom: smallerZoom,
													 size: tileSize)
							if tileLayersCache[tileSource]![largerTile] != nil && tileSource.hasCachedImage(for: largerTile) {
								break
							}
							if tileSource.hasCachedImage(for: largerTile) {
								let layer = MapTileLayer(tile: largerTile, tileSource: tileSource)
								self.layer.addSublayer(layer)
								tileLayersCache[tileSource]![largerTile] = layer
								break
							}
						}
					}
				}
			}
		}
	}
	
	private func remove(layer tileLayer: MapTileLayer, in tileSource: TileSource) {
		tileLayersCache[tileSource]?.removeValue(forKey: tileLayer.tile)
		layer.sublayers?.remove(object: tileLayer)
	}
	
	private var bestZoom: Int { Int(zoom.rounded()) }
	
	private func layers(in tileSource: TileSource, sorted: Bool = false) -> [MapTileLayer] {
		let layers = (tileLayersCache[tileSource] ?? [:]).values
		if sorted {
			return layers.sorted {
				abs($0.tile.zoom - bestZoom) > abs($1.tile.zoom - bestZoom)
			}
		} else {
			return Array(layers)
		}
	}
	
	private func removeLayersFromUnusedTileSources() {
		let allTileLayers = layer.sublayers?.compactMap( {$0 as? MapTileLayer } ) ?? []
		for tileLayer in allTileLayers {
			if !tileSources.contains(tileLayer.tileSource) {
				remove(layer: tileLayer, in: tileLayer.tileSource)
			}
		}
		for tileSource in tileLayersCache.keys {
			if !tileSources.contains(tileSource) {
				tileLayersCache[tileSource] = nil
			}
		}
	}
	
	private func removeUnusedTileLayers() {
		let margin = CGPoint(x: 220, y: 220)
		
		for tileSource in tileSources {
			let tileLayers = layers(in: tileSource)
			for tileLayer in tileLayers {
				// if tile is out of screen (with some margin), remove it
				if !bounds.insetBy(dx: -margin.x, dy: -margin.y).intersects(tileLayer.frame) {
					remove(layer: tileLayer, in: tileSource)
					continue
				}
			}
		}

		for tileSource in tileSources {
			let tileLayers = layers(in: tileSource, sorted: true)
			for tileLayer in tileLayers {
				if tileLayer.tile.zoom != bestZoom {
					// we're zooming out and can throw away unused smaller tiles
					let loadedLargerTiles = tileLayers.filter {
						$0 !== tileLayer && $0.loadState == .loaded && $0.tile.zoom < tileLayer.tile.zoom
						&& abs($0.tile.zoom - bestZoom) < abs(tileLayer.tile.zoom - bestZoom)
					}
					if loadedLargerTiles.contains(where: {$0.frame.contains(tileLayer.frame.insetBy(dx: 1, dy: 1))}) {
						// some existing larger and more appropriate tile overlaps this tile — remove it
						remove(layer: tileLayer, in: tileSource)
						continue
					}
				}
			}
		}

		
		for tileSource in tileSources {
			let tileLayers = layers(in: tileSource, sorted: true)
			for tileLayer in tileLayers {
				if tileLayer.tile.zoom != bestZoom && tileLayer.loadState != .loaded && !tileLayer.isAlmostLoaded && !tileSource.hasCachedImage(for: tileLayer.tile) {
					// remove layer if its zoom doesn't match and it's not loaded
					print("Removing \(tileLayer.tile) — not loaded and zoom doesn't match")
					remove(layer: tileLayer, in: tileSource)
				}
			}
		}
		
		//TODO: mask larger tiles to avoid overlaps
		for tileSource in tileSources {
			let tileLayers = layers(in: tileSource, sorted: true)
			for tileLayer in tileLayers {
				if tileLayer.tile.zoom != bestZoom {
					let tileVisiblePart = tileLayer.frame.intersection(bounds.insetBy(dx: -margin.x/2, dy: -margin.y/2))
					
					// don't bother with tiles that are out of screen
					if tileVisiblePart.width < 1 || tileVisiblePart.height < 1 {
						remove(layer: tileLayer, in: tileSource)
						continue
					}

					var isSafeToRemove = true

					// we're zooming in — delete larger tile when the area is fully covered with loaded smaller tiles
					let loadedSmallerTiles = tileLayers.filter {
						//TODO: we can't treat failed tiles as loaded because we must show larger tiles when zoom level is unavailable
						$0 !== tileLayer && ($0.loadState == .loaded/* || $0.loadState == .failed*/) && $0.tile.zoom > tileLayer.tile.zoom
					}

					// take some points in the visible area — if they are covered with something, suppose that entire region
					// is covered and it is safe to remove tile
					let checkPoints = [
						Point(0.12, 0.12), Point(0.12, 0.24), Point(0.12, 0.35), Point(0.12, 0.47), Point(0.12, 0.62), Point(0.12, 0.73), Point(0.12, 0.87),
						Point(0.24, 0.12), Point(0.24, 0.24), Point(0.24, 0.35), Point(0.24, 0.47), Point(0.24, 0.62), Point(0.24, 0.73), Point(0.24, 0.87),
						Point(0.35, 0.12), Point(0.35, 0.24), Point(0.35, 0.35), Point(0.35, 0.47), Point(0.35, 0.62), Point(0.35, 0.73), Point(0.35, 0.87),
						Point(0.47, 0.12), Point(0.47, 0.24), Point(0.47, 0.35), Point(0.47, 0.47), Point(0.47, 0.62), Point(0.47, 0.73), Point(0.47, 0.87),
						Point(0.62, 0.12), Point(0.62, 0.24), Point(0.62, 0.35), Point(0.62, 0.47), Point(0.62, 0.62), Point(0.62, 0.73), Point(0.62, 0.87),
						Point(0.73, 0.12), Point(0.73, 0.24), Point(0.73, 0.35), Point(0.73, 0.47), Point(0.73, 0.62), Point(0.73, 0.73), Point(0.73, 0.87),
						Point(0.87, 0.12), Point(0.87, 0.24), Point(0.87, 0.35), Point(0.87, 0.47), Point(0.87, 0.62), Point(0.87, 0.73), Point(0.87, 0.87),
					].map {
						tileVisiblePart.origin + Point(tileVisiblePart.width*$0.x, tileVisiblePart.height*$0.y)
					}
					
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
			let tileLayers = layers(in: tileSource)
			let indexAcrossMapSources = tileSources.count == 1
										  ? 0
										  : tileSources.count - tileSources.firstIndex(where: {$0.url == tileSource.url })!
			
			for layer in tileLayers {
				let scale = pow(2.0, zoom - Double(layer.tile.zoom))
				let size = Double(tileSource.tileSize) * scale
				layer.frame = CGRect(
					origin: projection.convert(point: layer.tile.offset, from: Double(layer.tile.zoom), to: zoom) - offset,
					size: CGSize(width: size, height: size))
				
				layer.zPosition = -abs(zoom.rounded() - Double(layer.tile.zoom)) - 25.0 * Double(indexAcrossMapSources) - 1
			}
		}
	}
	
	private func positionDrawingLayers() {
		for layer in drawingLayers.values {
			layer.position = projection.convert(point: drawnLayerOffset, from: Double(drawnLayerZoom), to: zoom) - offset
			let scale = pow(2.0, zoom - Double(drawnLayerZoom))
			layer.transform = CATransform3DMakeScale(scale, scale, 1)
		}
	}
	
	override func updateOffset(to camera: Camera) {
		super.updateOffset(to: camera)
		
		updateLayers()
		onScroll.send(.cameraUpdate)
	}
	
	override func didScroll() {
		animation.stop()
		updateLayers()
		onScroll.send(.drag)
	}
	
	private func updateLayers() {
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		
		addRequiredTileLayers()
		positionTileLayers()
		removeUnusedTileLayers()
		startLoadingRequiredTiles()
		prioritizeLoading()
		
		if drawnLayerZoom != zoom {
			redrawLayers()
		}
		positionDrawingLayers()
		
		CATransaction.commit()
	}
	
	
	private var oldBounds: CGRect = .zero
	public override func layoutSubviews() {
		super.layoutSubviews()
		
		guard bounds.width != 0 && bounds.height != 0 else {
			return
		}

		if oldBounds != .zero && bounds != oldBounds {
			// keep map center in the center when bounds changes
			let cameraAtOldCenter = Camera(center: coordinates(at: oldBounds.center), zoom: zoom)
			setCamera(cameraAtOldCenter, animated: false)
		}
		
		//TODO: called twice at init
		
		updateLayers()
		onScroll.send(.layoutChange)
		
		oldBounds = bounds
	}
	
	@discardableResult
	public func addMapLayer(id: AnyHashable = UUID(), _ configureLayer: @escaping ((CALayer?) -> (CALayer))) -> CALayer {
		let drawingLayer = configureLayer(nil)
		drawingLayersConfigs[id] = configureLayer
		drawingLayers[id] = drawingLayer
		layer.addSublayer(drawingLayer)
		redrawLayers()
		positionDrawingLayers()
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
	
	public func redrawLayers() {
		for (key, layer) in drawingLayers {
			let _ = drawingLayersConfigs[key]?(layer)
		}
		
		drawnLayerZoom = zoom
	}
	
	private func startLoadingRequiredTiles() {
		for tileSource in tileSources {
			let tileLayers = layers(in: tileSource)
			for layer in tileLayers {
				if layer.loadState == .idle || layer.loadState == .failedNeedsRetry {
					if tileSource.hasCachedImage(for: layer.tile) {
						// load right now if it's cached
						layer.loadImage()
					} else {
						layer.markScheduled()
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {[weak self, weak layer] in
							if let self = self, let layer = layer {
								layer.loadImage(priority: self.priority(for: layer))
							}
						}
					}
				}
			}
		}
	}
	
	private func priority(for layer: MapTileLayer) -> ImageRequest.Priority {
		if abs(layer.tile.zoom - bestZoom) >= 2 {
			return .veryLow
		}
		else if layer.tile.zoom != bestZoom {
			return .low
		}
		else if !bounds.intersects(layer.frame) {
			return .normal
		}
		else if tileSources.count > 1 && layer.tileSource.url == tileSources[0].url {
			return .veryHigh
		} else {
			return .high
		}
	}
	
	private func prioritizeLoading() {
		for tileSource in tileSources {
			let tileLayers = layers(in: tileSource)
			for layer in tileLayers {
				layer.loadTaskPriority = priority(for: layer)
			}
		}
	}
}



}
}
