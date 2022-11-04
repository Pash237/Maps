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
	private let projection = SphericalMercator()
	
	private var tileLayersCache: [String: [MapTile: MapTileLayer]] = [:]
	
	public var tileSources: [TileSource] {
		didSet {
			removeLayersFromUnusedTileSources()
			updateLayers()
		}
	}
	
	private var drawingLayersConfigs: [((CALayer?) -> (CALayer))] = []
	private var drawingLayers: [CALayer] = []
	private var drawnLayerOffset: CGPoint = .zero
	private var drawnLayerZoom: Double = 11
	
	private var bag = Set<AnyCancellable>()
	
	public var onScroll: ((ScrollReason) -> ())? = nil
	
	private var animation = SpringAnimation<Camera>(response: 0.4, dampingRatio: 1.0)
	
	public var camera: Camera {
		get {
			return Camera(center: coordinates(at: bounds.center), zoom: zoom)
		}
		set {
			var value = newValue
			if newValue.zoom == zoom && animation.toValue.zoom != 0 {
				// if we doesn't seem to change zoom, use target zoom value
				value.zoom = animation.toValue.zoom
			}
			
			if animation.hasResolved() {
				animation.toValue = value
				animation.stop(resolveImmediately: true, postValueChanged: true)
			} else {
				// if we have ongoing animation, redirect it to a new location
				//TODO: this may result in infinite animation if camera updates are more frequent than animation duration
				animation.toValue = value
			}
		}
	}
	
	public init(frame: CGRect, tileSources: [TileSource], camera: Camera) {
		self.tileSources = tileSources
		
		super.init(frame: frame)
		
		self.camera = camera
		updateOffset(to: camera)

		NotificationCenter.default.publisher(for: .mapTileLoaded)
			.throttle(for: 0.005, scheduler: DispatchQueue.main, latest: true)
			.sink() {[weak self] _ in
				self?.removeUnusedTileLayers()
			}
			.store(in: &bag)
		
		animation.resolvingEpsilon = 0.0001
		animation.onValueChanged { [weak self] in self?.updateOffset(to: $0) }
	}

	public convenience init(frame: CGRect, tileSource: TileSource, camera: Camera) {
		self.init(frame: frame, tileSources: [tileSource], camera: camera)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	private func updateOffset(to camera: Camera) {
		stopDecelerating()
		zoom = camera.zoom
		offset = point(at: camera.center) - bounds.center
		updateLayers()
		onScroll?(.cameraUpdate)
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
			if tileLayersCache[tileSource.url] == nil {
				tileLayersCache[tileSource.url] = [:]
			}
		}
		
		for tileSource in tileSources {
			for x in Int(min.x)...Int(max.x) {
				for y in Int(min.y)...Int(max.y) {
					let tile = MapTile(x: x, y: y, zoom: requiredZoom, size: tileSize)
					
					if tileLayersCache[tileSource.url]![tile] == nil {
						let layer = MapTileLayer(tile: tile, tileSource: tileSource)
						self.layer.addSublayer(layer)
						tileLayersCache[tileSource.url]![tile] = layer
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
							if tileLayersCache[tileSource.url]![largerTile] != nil && tileSource.hasCachedImage(for: largerTile) {
								break
							}
							if tileSource.hasCachedImage(for: largerTile) {
								let layer = MapTileLayer(tile: largerTile, tileSource: tileSource)
								self.layer.addSublayer(layer)
								tileLayersCache[tileSource.url]![largerTile] = layer
								break
							}
						}
					}
				}
			}
		}
	}
	
	private func remove(layer tileLayer: MapTileLayer, in tileSource: TileSource) {
		tileLayersCache[tileSource.url]?.removeValue(forKey: tileLayer.tile)
		layer.sublayers?.remove(object: tileLayer)
	}
	
	private var bestZoom: Int { Int(zoom.rounded()) }
	
	private func layers(in tileSource: TileSource, sorted: Bool = false) -> [MapTileLayer] {
		let layers = (tileLayersCache[tileSource.url] ?? [:]).values
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
		for key in tileLayersCache.keys {
			if !tileSources.contains(where: {$0.url == key}) {
				tileLayersCache[key] = nil
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
						$0 !== tileLayer && $0.isLoaded && $0.tile.zoom < tileLayer.tile.zoom
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
				if tileLayer.tile.zoom != bestZoom && !tileLayer.isLoaded && !tileLayer.isAlmostLoaded && !tileSource.hasCachedImage(for: tileLayer.tile) {
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
						$0 !== tileLayer && $0.isLoaded && $0.tile.zoom > tileLayer.tile.zoom
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
				
				layer.zPosition = -abs(zoom.rounded() - Double(layer.tile.zoom)) - 25.0 * Double(indexAcrossMapSources)
			}
		}
	}
	
	private func positionDrawingLayers() {
		for layer in drawingLayers {
			layer.position = projection.convert(point: drawnLayerOffset, from: Double(drawnLayerZoom), to: zoom) - offset
			let scale = pow(2.0, zoom - Double(drawnLayerZoom))
			layer.transform = CATransform3DMakeScale(scale, scale, 1)
			layer.zPosition = 1
		}
	}

	public func coordinates(at screenPoint: Point) -> Coordinates {
		projection.coordinates(from: offset + screenPoint, at: zoom, tileSize: tileSize)
	}
	
	public func point(at coordinates: Coordinates) -> Point {
		projection.point(at: zoom, tileSize: tileSize, from: coordinates)
	}
	public func screenPoint(at coordinates: Coordinates) -> Point {
		point(at: coordinates) - offset
	}
	
	public var coordinateBounds: CoordinateBounds {
		CoordinateBounds(northeast: coordinates(at: .zero),
						 southwest: coordinates(at: CGPoint(bounds.width, bounds.height)))
	}
	
	override func didScroll() {
		animation.stop()
		updateLayers()
		onScroll?(.drag)
	}
	
	private func updateLayers() {
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
		
		CATransaction.setDisableActions(false)
	}
	
	
	private var oldBounds: CGRect = .zero
	public override func layoutSubviews() {
		super.layoutSubviews()
		
		guard bounds.width != 0 && bounds.height != 0 else {
			return
		}

		if oldBounds != .zero && bounds != oldBounds {
			let cameraAtOldCenter = Camera(center: coordinates(at: oldBounds.center), zoom: zoom)
			setCamera(cameraAtOldCenter, animated: false)
		}
		
		//TODO: called twice at init
		
		updateLayers()
		onScroll?(.layoutChange)
		
		oldBounds = bounds
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
	
	public func redrawLayers() {
		for (i, layer) in drawingLayers.enumerated() {
			let _ = drawingLayersConfigs[i](layer)
		}
		
		drawnLayerZoom = zoom
	}
	
	private func startLoadingRequiredTiles() {
		for tileSource in tileSources {
			let tileLayers = layers(in: tileSource)
			for layer in tileLayers {
				if !layer.isLoaded && !layer.isLoading && !layer.isScheduledForLoading {
					if tileSource.hasCachedImage(for: layer.tile) {
						// load right now if it's cached
						layer.loadImage()
					} else {
						layer.isScheduledForLoading = true
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
	
	public func setCamera(_ newCamera: Camera, animated: Bool = true) {
		guard animated else {
			camera = newCamera
			return
		}
		
		animation.updateValue(to: camera)
		animation.toValue = newCamera
		
		animation.start()
	}
}



}
}
