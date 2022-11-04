//
//  MapTileLayer.swift
//  maps
//
//  Created by Pavel Alexeev on 01.06.2022.
//

import UIKit
import Nuke

public struct MapTile: Equatable, Hashable {
	var x: Int
	var y: Int
	var zoom: Int
	var size = 512
	
	var offset: Point {
		Point(x: x * size, y: y * size)
	}
	
	public init(x: Int, y: Int, zoom: Int, size: Int = 512) {
		self.x = x
		self.y = y
		self.zoom = zoom
		self.size = size
	}
}

extension Notification.Name {
	static let mapTileLoaded = NSNotification.Name("MapTileLoaded")
}

class MapTileLayer: CALayer {
	private(set) var tile: MapTile
	private(set) var tileSource: TileSource
	private(set) var isLoaded = false
	private(set) var isLoading = false
	var isScheduledForLoading = false
	
	private var imageTask: ImageTask?
	
	init(tile: MapTile, tileSource: TileSource) {
		self.tile = tile
		self.tileSource = tileSource
		super.init()
		
		anchorPoint = .zero
		contentsGravity = .resize
		frame = CGRect(x: 0, y: 0, width: tile.size, height: tile.size)
		isOpaque = true
		
	}
	
	func loadImage(priority: ImageRequest.Priority? = nil) {
		isLoading = true
		imageTask = tileSource.loadImage(for: tile) {[weak self] result in
			if let cgImage = try? result.get().image.cgImage {
				guard let self = self else {return}
				self.contents = cgImage
				self.isLoaded = true
				self.isLoading = false
				self.imageTask = nil
				NotificationCenter.default.post(name: .mapTileLoaded, object: self)
			}
		}
		if let priority = priority {
			imageTask?.priority = priority
		}
	}
	
	func cancelLoading() {
		imageTask?.cancel()
		imageTask = nil
		isLoading = false
		isScheduledForLoading = false
	}
	
	var isAlmostLoaded: Bool {
		if let task = imageTask {
			return task.totalUnitCount > 0 && Double(task.completedUnitCount)/Double(task.totalUnitCount) > 0.4
		}
		return isLoaded
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
