//
//  MapTileLayer.swift
//  maps
//
//  Created by Pavel Alexeev on 01.06.2022.
//

import UIKit

struct MapTile: Equatable, Hashable {
	var x: Int
	var y: Int
	var zoom: Int
	var size = 512
	
	var offset: Point {
		Point(x: x * size, y: y * size)
	}
}

extension Notification.Name {
	static let mapTileLoaded = NSNotification.Name("MapTileLoaded")
}

class MapTileLayer: CALayer {
	var tile: MapTile
	var tileSource: TileSource
	@Published var isLoaded = false
	
	init(tile: MapTile, tileSource: TileSource) {
		self.tile = tile
		self.tileSource = tileSource
		super.init()
		
		anchorPoint = .zero
		contentsGravity = .resize
		frame = CGRect(x: 0, y: 0, width: tile.size, height: tile.size)
		isOpaque = true
		
		Task {
			//TODO: throttle
			//TODO: load most needed tiles first
			await loadImage()
		}
	}
	
	private func loadImage() async {
		//TODO: retry loading when network is available
		
		if let cgImage = try? await tileSource.loadImage(for: tile) {
//			print("Loaded \(cgImage.width)x\(cgImage.height) from \(url)")
			await MainActor.run {
				contents = cgImage
				isLoaded = true
				NotificationCenter.default.post(name: .mapTileLoaded, object: self)
			}
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
