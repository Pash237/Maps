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
	public var onTapOnLayer = PassthroughSubject<AnyHashable, Never>()
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
		
		onScroll
			.throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
			.sink() {[weak self] _ in
				self?.redrawLayers()
			}
			.store(in: &bag)
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
//						let frame = CGRect(
//							origin: projection.convert(point: tile.offset, from: Double(tile.zoom), to: zoom) - offset,
//							size: CGSize(width: size, height: size))
//						print("adding tile \(tile) for \(tileSource.title), cached: \(tileSource.hasCachedImage(for: tile)), frame: \(frame.pretty)")
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
								
//								print("      adding larger tile \(largerTile) while tile \(tile) is not loaded")
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
		
//		if tileLayersCache[tileSources[0]]!.values.contains(where: {$0.tile.zoom != bestZoom}) {
//			for tileSource in tileSources {
//				let tileLayers = layers(in: tileSource)
//				print("\(tileLayers.count) layers in \(tileSource.title):")
//				for layer in tileLayers {
//					print("    \(layer.tile) \(layer.isLoaded ? "✓" : "✕") \(tileSource.hasCachedImage(for: layer.tile) ? "✓" : "✕"), frame: \(layer.frame.pretty)")
//				}
//			}
//		}
//
//		print("Removing unused tiles, best zoom: \(bestZoom)...")
		
		for tileSource in tileSources {
			let tileLayers = layers(in: tileSource)
			for tileLayer in tileLayers {
				// if tile is out of screen (with some margin), remove it
				if !bounds.insetBy(dx: -margin.x, dy: -margin.y).intersects(tileLayer.frame) {
//					print("Removing \(tileLayer.tile) — out of screen: \(tileLayer.frame.pretty)")
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
//						print("Removing \(tileLayer.tile) — some existing larger tile overlaps this tile")
						remove(layer: tileLayer, in: tileSource)
						continue
					}
				}
			}
		}

//		for tileSource in tileSources {
//			let tileLayers = layers(in: tileSource, sorted: true)
//			for tileLayer in tileLayers {
//				if tileLayer.isLoaded && tileLayer.tile.zoom < bestZoom {
//
//					let smallerNotLoadedTiles = layers(in: tileSource, sorted: true).filter {!$0.isLoaded && $0.tile.zoom > tileLayer.tile.zoom}
//
//					let maskPath = CGMutablePath()
//					for smallerTile in smallerNotLoadedTiles {
//	//					let rectInLargerTile = tileLayer.convert(smallerTile.frame, to: tileLayer)
//	//					print("rectInLargerTile = \(rectInLargerTile)")
//						let rectInLargerTile = CGRect(origin: smallerTile.frame.origin - tileLayer.frame.origin, size: smallerTile.frame.size)
//						maskPath.addRect(rectInLargerTile)
//
////						print("rectInLargerTile = \(rectInLargerTile)")
//					}
//					let maskLayer = (tileLayer.mask as? CAShapeLayer) ?? CAShapeLayer()
//					maskLayer.frame = tileLayer.bounds
//					maskLayer.path = maskPath
//					tileLayer.mask = maskLayer
//					tileLayer.removeAllAnimations()
//					if maskLayer.superlayer != tileLayer {
//						tileLayer.addSublayer(maskLayer)
//					}
//				} else {
//					tileLayer.mask?.removeFromSuperlayer()
//					tileLayer.mask = nil
//				}
//			}
//		}
		
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
//						print("Removing \(tileLayer.tile) — out of screen, frame: \(tileLayer.frame.pretty), visible part: \(tileVisiblePart.pretty)")
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
//						print("Removing \(tileLayer.tile) — smaller more appropriate tiles are covering this area")
//						print("    tileLayer.frame: \(tileLayer.frame.pretty)")
//						print("    visible part: \(tileVisiblePart.pretty)")
//						print("    check points: \(checkPoints)")
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
	
	private func positionDrawingLayer(id: AnyHashable) {
		guard let layer = drawingLayers[id] else {
			return
		}
		layer.position = projection.convert(point: drawnLayerOffset, from: Double(drawnLayerZoom), to: zoom) - offset
		let scale = pow(2.0, zoom - Double(drawnLayerZoom))
		layer.transform = CATransform3DMakeScale(scale, scale, 1)
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
//		print("did scroll, zoom: \(zoom), offset: \(offset.pretty)")
		
		let minZoom = UIScreen.main.bounds.height/2 / Double(tileSize)
		if zoom < minZoom {
			zoom = minZoom
			stopDecelerating()
		}

		if offset.y < 0 {
			offset.y = 0
			stopDecelerating()
		}
		if offset.y > mapWidth - bounds.height {
			offset.y = mapWidth - bounds.height
			stopDecelerating()
		}
		
		updateLayers()
		onScroll.send(.drag)
	}
	
	private var mapWidth: Double {
		Double(tileSize) * pow(2, zoom)
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
		//remove existent layer if it's present
		drawingLayers[id]?.removeFromSuperlayer()
		
		let drawingLayer = configureLayer(nil)
		drawingLayersConfigs[id] = configureLayer
		drawingLayers[id] = drawingLayer
		layer.addSublayer(drawingLayer)
		
		redrawLayer(id: id)
		positionDrawingLayer(id: id)
		
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
	
	public func redrawLayer(id: AnyHashable) {
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		
		if let layer = drawingLayers[id] {
			let _ = drawingLayersConfigs[id]?(layer)
		}
		
		drawnLayerZoom = zoom
		
		CATransaction.commit()
	}
	
	public func redrawLayers() {	
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		
		for (key, layer) in drawingLayers {
			let _ = drawingLayersConfigs[key]?(layer)
		}
		
		drawnLayerZoom = zoom
		
		//TODO: avoid unnecessary transactions
		CATransaction.commit()
	}
	
	private func layerIds(at coordinates: Coordinates, threshold: CGFloat = 30.0) -> [(key: AnyHashable, distance: CGFloat)] {
		drawingLayers.compactMap { key, layer in
			let point = projection.point(at: zoom, from: coordinates)
			if let distance = layer.distance(to: point), distance < threshold {
				return (key, distance)
			} else {
				return nil
			}
		}
	}
	
	public func layerId(at coordinates: Coordinates) -> AnyHashable? {
		let touchedLayerIds = layerIds(at: coordinates)
		let closest = touchedLayerIds.min(by: {
			$0.distance < $1.distance
		})
		
		return closest?.key
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
	
	override func onSingleTap(point: CGPoint) {
		let coordinates = coordinates(at: point)
		onTap.send(coordinates)
		if let id = layerId(at: coordinates) {
			onTapOnLayer.send(id)
		}
	}
	
	override func onLongPress(point: CGPoint) {
		let coordinates = coordinates(at: point)
		onLongPress.send(coordinates)
	}
}


//-------------------


class Logger {
	static let shared = Logger()
	
	private lazy var shortFormatter: DateFormatter = {
		var formatter = DateFormatter()
		formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "HH:mm:ss.SSS", options: 0, locale: Locale(identifier: "en_US"))
		return formatter
	}()
	
	func log(_ string: String) {
		let delimeter = Thread.isMainThread ? "|" : "¦"
		let stringWithDate = "\(shortFormatter.string(from: Date())) \(delimeter) \(string)"
		Swift.print(stringWithDate)
	}
}

func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
	if _isDebugAssertConfiguration() {
		if let firstItem = items.first {
			Logger.shared.log(firstItem as? String ?? "\(firstItem)")
		} else {
			Logger.shared.log("")
		}
	}
}
