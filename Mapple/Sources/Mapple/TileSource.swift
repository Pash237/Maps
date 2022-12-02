//
//  TileSource.swift
//  maps
//
//  Created by Pavel Alexeev on 09.06.2022.
//

import Foundation
import UIKit
import Nuke

public struct TileSource: Equatable, Hashable {
	public let title: String
	public let url: String
	public let tileSize: Int	//size in points on screen
	public let minZoom: Int
	public let maxZoom: Int
	
	private let imagePipeline: ImagePipeline
	
	private static var cachedImageLookup: [TileSource:[MapTile:Bool]] = [:]

	public init(title: String, url: String, tileSize: Int = 256, minZoom: Int = 0, maxZoom: Int = 22, imagePipeline: ImagePipeline = .defaultTileLoader) {
		self.title = title
		self.url = url
		self.tileSize = tileSize
		self.minZoom = minZoom
		self.maxZoom = maxZoom
		self.imagePipeline = imagePipeline
		
		if Self.cachedImageLookup[self] == nil {
			Self.cachedImageLookup[self] = [:]
		}
	}

	public func url(for tile: MapTile) -> URL {
		URL(string: url
			.replacingOccurrences(of: "{x}", with: "\(tile.x)")
			.replacingOccurrences(of: "{y}", with: "\(tile.y)")
			.replacingOccurrences(of: "{z}", with: "\(tile.zoom)")
			.replacingOccurrences(of: "{ratio}", with: UIScreen.main.scale > 1 ? "@2x" : "")
			.replacingOccurrences(of: "{server}", with: ["a", "b", "c"][abs(tile.x + tile.y + tile.zoom) % 3])
			.replacingOccurrences(of: "{abc}", with: ["a", "b", "c"][abs(tile.x + tile.y + tile.zoom) % 3])
			.replacingOccurrences(of: "{abcd}", with: ["a", "b", "c", "d"][abs(tile.x + tile.y + tile.zoom) % 4])
			.replacingOccurrences(of: "{012}", with: ["0", "1", "2"][abs(tile.x + tile.y + tile.zoom) % 3])
			.replacingOccurrences(of: "{0123}", with: ["0", "1", "2", "3"][abs(tile.x + tile.y + tile.zoom) % 4])
			.replacingOccurrences(of: "{123}", with: ["1", "2", "3"][abs(tile.x + tile.y + tile.zoom) % 3])
			.replacingOccurrences(of: "{1234}", with: ["1", "2", "3", "4"][abs(tile.x + tile.y + tile.zoom) % 4])
		)!
	}

	public func hash(into hasher: inout Hasher) {
		hasher.combine(url.hash)
	}
	
	func loadImage(for tile: MapTile, completion: @escaping ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)) -> ImageTask {
		let url = url(for: tile)
		return imagePipeline.loadImage(with: url, completion: {result in
			if case .success = result {
				Self.cachedImageLookup[self]?[tile] = true
			}
			completion(result)
		})
	}
	
	func hasCachedImage(for tile: MapTile) -> Bool {
		if let cached = Self.cachedImageLookup[self]?[tile] {
			return cached
		}
		
		let url = url(for: tile)
		let contains = imagePipeline.cache.containsCachedImage(for: ImageRequest(url: url))
		Self.cachedImageLookup[self]?[tile] = contains
		return contains
	}
	
	func cachedImage(for tile: MapTile) -> CGImage? {
		let url = url(for: tile)
		return imagePipeline.cache.cachedImage(for: ImageRequest(url: url))?.image.cgImage
	}
	
	public static func == (lhs: TileSource, rhs: TileSource) -> Bool {
		lhs.title == rhs.title && lhs.url == rhs.url
	}
}

public extension ImagePipeline {
	static var defaultTileLoader: ImagePipeline = {
		let dataLoader: DataLoader = {
			let config = URLSessionConfiguration.default
			config.urlCache = nil
			config.waitsForConnectivity = true
			return DataLoader(configuration: config)
		}()

		let diskCache = try! DataCache(name: "com.pash.maps")
		diskCache.sizeLimit = 512 * 1024 * 1024  // 512 MB
		diskCache.sweepInterval = 12 * 60 * 60   // 12 hours

		return ImagePipeline() {
			$0.dataLoader = dataLoader
			$0.dataCache = diskCache
			$0.dataLoadingQueue.maxConcurrentOperationCount = 6
		}
	}()
}
