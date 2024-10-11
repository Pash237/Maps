//
//  TileMapLayers.swift
//  
//
//  Created by Pavel Alexeev on 15.07.2023.
//

import UIKit
import Combine
import CoreLocation
import Nuke

class TileMapView: UIView, MapViewLayer {
	private(set) var offset: Point = .zero
	private(set) var zoom: Double = 11
	private(set) var rotation: Radians = 0.0
	var projection = SphericalMercator()
	
	private var tileLayersCache: [TileSource: [MapTile: MapTileLayer]] = [:]
	private var bag = Set<AnyCancellable>()
	
	override init(frame: CGRect) {
		super.init(frame: frame)
		
		isUserInteractionEnabled = false
		layer.allowsGroupOpacity = true
		NotificationCenter.default.publisher(for: .mapTileLoaded)
			.throttle(for: 0.005, scheduler: DispatchQueue.main, latest: true)
			.sink() {[weak self] _ in
				self?.removeUnusedTileLayers()
			}
			.store(in: &bag)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	var tileSources: [TileSource] = [] {
		didSet {
			removeLayersFromUnusedTileSources()
			updateLayers()
		}
	}
	
	public func update(offset: Point, zoom: Double, rotation: Radians) {
		self.offset = offset
		self.zoom = zoom
		self.rotation = rotation
		
		updateLayers()
	}
	
	
	private func updateLayers() {
		guard offset != .zero else {
			return
		}
		addRequiredTileLayers()
		positionTileLayers()
		removeUnusedTileLayers()
		startLoadingRequiredTiles()
		prioritizeLoading()
	}
	
	private func addRequiredTileLayers() {
		for tileSource in tileSources {
			let requiredZoom: Int = Int(zoom.rounded()).clamped(to: tileSource.zoomRange)
			let requiredScale = pow(2.0, Double(requiredZoom) - zoom)
			let size = Double(tileSource.tileSize)
			let margin = loadMargin
			let topLeft = projection.convert(point: offset - margin, from: zoom, to: Double(requiredZoom))
			
			let min = topLeft / size
			let max = (topLeft + Point(x: bounds.width, y: bounds.height)*requiredScale + margin*2*requiredScale) / size
			
			if tileLayersCache[tileSource] == nil {
				tileLayersCache[tileSource] = [:]
			}
		
			for x in Int(min.x)...Int(max.x) {
				for y in Int(min.y)...Int(max.y) {
					guard requiredZoom >= 0, x >= 0, y >= 0 else {
						continue
					}
					let tile = MapTile(x: x, y: y, zoom: requiredZoom, size: tileSource.tileSize)
					
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
													 size: tileSource.tileSize)
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
	
	private var loadMargin: CGPoint {
		// good enough
		let extra = abs(sin(rotation) * (bounds.height - bounds.width))/2
		return CGPoint(x: 200 + extra, y: 200 + extra)
	}
	
	private func removeUnusedTileLayers() {
		let margin = loadMargin + CGPoint(x: 20, y: 20)
		
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
			let bestZoom = bestZoom.clamped(to: tileSource.zoomRange)
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
			let bestZoom = bestZoom.clamped(to: tileSource.zoomRange)
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
			let bestZoom = bestZoom.clamped(to: tileSource.zoomRange)
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
				
				let zPosition = -abs(zoom.rounded() - Double(layer.tile.zoom)) - 25.0 * Double(indexAcrossMapSources) - 1
				if layer.zPosition != zPosition {
					layer.zPosition = zPosition
				}
			}
		}
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
