//
//  TileSource.swift
//  maps
//
//  Created by Pavel Alexeev on 09.06.2022.
//

import Foundation
import UIKit
import Nuke

public struct TileSource {
	public var title: String
	public var url: String
	public var tileSize: Int = 256	//size in points on screen
	public var minZoom: Int = 0
	public var maxZoom: Int = 22
	
	public init(title: String, url: String, tileSize: Int = 256, minZoom: Int = 0, maxZoom: Int = 22) {
		self.title = title
		self.url = url
		self.tileSize = tileSize
		self.minZoom = minZoom
		self.maxZoom = maxZoom
	}
	
	func url(for tile: MapTile) -> URL {
		URL(string: url
			.replacingOccurrences(of: "{x}", with: "\(tile.x)")
			.replacingOccurrences(of: "{y}", with: "\(tile.y)")
			.replacingOccurrences(of: "{z}", with: "\(tile.zoom)")
			.replacingOccurrences(of: "{ratio}", with: UIScreen.main.scale > 1 ? "@2x" : "")
		)!
	}
	
	private let imagePipeline: ImagePipeline = {
		let dataLoader: DataLoader = {
			let config = URLSessionConfiguration.default
			config.urlCache = nil
			return DataLoader(configuration: config)
		}()
		
		let diskCache = try! DataCache(name: "com.pash.maps")
		diskCache.sizeLimit = 512 * 1024 * 1024  // 512 MB
		diskCache.sweepInterval = 12 * 60 * 60   // 12 hours
		
		return ImagePipeline() {
			$0.dataLoader = dataLoader
			$0.dataCache = diskCache
		}
	}()
	
	func loadImage(for tile: MapTile) async throws -> CGImage? {
		let url = url(for: tile)
		return (try await imagePipeline.image(for: url)).image.cgImage
	}
}
