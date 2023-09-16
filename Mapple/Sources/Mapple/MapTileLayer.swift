//
//  MapTileLayer.swift
//  maps
//
//  Created by Pavel Alexeev on 01.06.2022.
//

import UIKit
import Nuke

public struct MapTile: Equatable, Hashable {
	public var x: Int
	public var y: Int
	public var zoom: Int
	public var size = 512
	
	private let hash: Int
	
	public init(x: Int, y: Int, zoom: Int, size: Int = 512) {
		self.x = x
		self.y = y
		self.zoom = zoom
		self.size = size
		self.hash = (1 << zoom)*(1 << zoom) + y * (1 << zoom) + x
	}
	
	public var offset: Point {
		Point(x: x * size, y: y * size)
	}
	
	public func hash(into hasher: inout Hasher) {
		hasher.combine(hash)
	}
	
	public static func == (lhs: MapTile, rhs: MapTile) -> Bool {
		lhs.hash == rhs.hash
	}
}

extension Notification.Name {
	static let mapTileLoaded = NSNotification.Name("MapTileLoaded")
}

class MapTileLayer: CALayer {
	
	enum LoadState {
		case idle
		case scheduled
		case loading
		case loaded
		case failedNeedsRetry
		case failed
	}
	
	private(set) var tile: MapTile
	private(set) var tileSource: TileSource
	private(set) var loadState: LoadState = .idle
	
	private var imageTask: ImageTask?
	
	init(tile: MapTile, tileSource: TileSource) {
		self.tile = tile
		self.tileSource = tileSource
		super.init()
		
		anchorPoint = .zero
		contentsGravity = .resize
		frame = CGRect(x: 0, y: 0, width: tile.size, height: tile.size)
		isOpaque = false
	}
	
	func loadImage(priority: ImageRequest.Priority? = nil) {
		loadState = .loading
		imageTask = tileSource.loadImage(for: tile) {[weak self] result in
			guard let self = self else {return}
			
			do {
				let cgImage = try result.get().image.cgImage
				self.contents = cgImage
				self.loadState = .loaded
				self.imageTask = nil
				NotificationCenter.default.post(name: .mapTileLoaded, object: self)
			} catch ImagePipeline.Error.dataLoadingFailed(let loadError) {
				self.imageTask = nil
				
				print("Error loading tile \(self.tile): \(loadError)")

				// treat 400 & 404 errors
				if case let .statusCodeUnacceptable(statusCode) = loadError as? DataLoader.Error, statusCode == 404 || statusCode == 400 {
					//TODO: remember that this tile is failed and don't try to load it next time
					self.loadState = .failed
					NotificationCenter.default.post(name: .mapTileLoaded, object: self)
				} else {
					self.loadState = .failedNeedsRetry
				}
					
			} catch {
				print("other error: \(error)")
			}
		}
		if let priority = priority {
			imageTask?.priority = priority
		}
	}
	
	func cancelLoading() {
		imageTask?.cancel()
		imageTask = nil
		loadState = .idle
	}
	
	func markScheduled() {
		loadState = .scheduled
	}
	
	var isAlmostLoaded: Bool {
		if let task = imageTask {
			return task.progress.total > 0 && Double(task.progress.fraction) > 0.4
		}
		return loadState == .loaded
	}
	
	deinit {
		if let task = imageTask, !isAlmostLoaded {
			task.cancel()
		}
	}
	
	var loadTaskPriority: ImageRequest.Priority {
		get {
			imageTask?.priority ?? .normal
		}
		set {
			imageTask?.priority = newValue
		}
	}
	
	override init(layer: Any) {
		if let layer = layer as? MapTileLayer {
			tile = layer.tile
			tileSource = layer.tileSource
		} else {
			tile = MapTile(x: 0, y: 0, zoom: 10)
			tileSource = TileSource(title: "", url: "")
		}
		super.init(layer: layer)
		
		if let layer = layer as? MapTileLayer {
			tile = layer.tile
			tileSource = layer.tileSource
			frame = layer.frame
			position = layer.position
			contents = layer.contents
		}
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
