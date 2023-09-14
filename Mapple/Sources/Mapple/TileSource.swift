//
//  TileSource.swift
//  maps
//
//  Created by Pavel Alexeev on 09.06.2022.
//

import Foundation
import UIKit
import Nuke

public final class TileSource: Equatable, Hashable, ImagePipelineDelegate {
	public let title: String
	public let url: String
	public let tileSize: Int	//size in points on screen
	public let minZoom: Int
	public let maxZoom: Int
	
	private var imagePipeline: ImagePipeline!
	private let hash: Int
	
	private static var cachedImageLookup: [TileSource:[MapTile:Bool]] = [:]

	public init(title: String, url: String, tileSize: Int = 256, minZoom: Int = 0, maxZoom: Int = 22, imagePipeline: ImagePipeline? = nil) {
		self.title = title
		self.url = url
		self.tileSize = tileSize
		self.minZoom = minZoom
		self.maxZoom = maxZoom
		self.hash = url.hash
		self.imagePipeline = imagePipeline ?? defaultImagePipeline()
		
		if Self.cachedImageLookup[self] == nil {
			Self.cachedImageLookup[self] = [:]
			preheatCacheLookup()
		}
	}

	public func url(for tile: MapTile) -> URL {
		URL(string: url
			.replacingOccurrences(of: "{x}", with: "\(tile.x)")
			.replacingOccurrences(of: "{y}", with: "\(tile.y)")
			.replacingOccurrences(of: "{z}", with: "\(tile.zoom)")
			.replacingOccurrences(of: "{zoom}", with: "\(tile.zoom)")
			.replacingOccurrences(of: "{ratio}", with: UIScreen.main.scale > 1 ? "@2x" : "")
			.replacingOccurrences(of: "{server}", with: ["a", "b", "c"][abs(tile.x + tile.y + tile.zoom) % 3])
			.replacingOccurrences(of: "{abc}", with: ["a", "b", "c"][abs(tile.x + tile.y + tile.zoom) % 3])
			.replacingOccurrences(of: "{abcd}", with: ["a", "b", "c", "d"][abs(tile.x + tile.y + tile.zoom) % 4])
			.replacingOccurrences(of: "{012}", with: ["0", "1", "2"][abs(tile.x + tile.y + tile.zoom) % 3])
			.replacingOccurrences(of: "{0123}", with: ["0", "1", "2", "3"][abs(tile.x + tile.y + tile.zoom) % 4])
			.replacingOccurrences(of: "{123}", with: ["1", "2", "3"][abs(tile.x + tile.y + tile.zoom) % 3])
			.replacingOccurrences(of: "{1234}", with: ["1", "2", "3", "4"][abs(tile.x + tile.y + tile.zoom) % 4])
			//TODO: support {switch:a,b,c} and [abc]
			//TODO: support date formats
		)!
	}

	public func hash(into hasher: inout Hasher) {
		hasher.combine(hash)
	}
	
	public func loadImage(for tile: MapTile, completion: @escaping ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)) -> ImageTask {
		let url = url(for: tile)
		var request = ImageRequest(url: url)
		request.userInfo = [
			.tileKey: tile,
			.tileSourceIdKey: hash
		]
		return imagePipeline.loadImage(with: request, completion: {result in
			if case .success = result {
				Self.cachedImageLookup[self]?[tile] = true
			}
			completion(result)
		})
	}
	
	public func possiblyHasCachedImage(for tile: MapTile) -> Bool {
		Self.cachedImageLookup[self]?[tile] ?? false
	}
	
	public func possiblyCachedTiles(for zoom: Int) -> [MapTile] {
		Self.cachedImageLookup[self]?.keys.filter {
			$0.zoom == zoom
		} ?? []
	}
	
	public func hasCachedImage(for tile: MapTile) -> Bool {
		if let cached = Self.cachedImageLookup[self]?[tile] {
			return cached
		}
		
		let url = url(for: tile)
		var request = ImageRequest(url: url)
		request.userInfo = [
			.tileKey: tile,
			.tileSourceIdKey: hash
		]
		let contains = imagePipeline.cache.containsCachedImage(for: request)
		Self.cachedImageLookup[self]?[tile] = contains
		return contains
	}
	
	public func cachedImage(for tile: MapTile) -> CGImage? {
		let url = url(for: tile)
		return imagePipeline.cache.cachedImage(for: ImageRequest(url: url))?.image.cgImage
	}
	
	public static func == (lhs: TileSource, rhs: TileSource) -> Bool {
		lhs.hash == rhs.hash
	}
	
	private var tileCacheDirectory: URL {
		FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
			.appendingPathComponent("TileCache", isDirectory: true)
			.appendingPathComponent(title, isDirectory: true)
	}
	
	private func defaultImagePipeline() -> ImagePipeline {
		let dataLoader: DataLoader = {
			let config = URLSessionConfiguration.default
			config.urlCache = nil
			config.waitsForConnectivity = true
			return DataLoader(configuration: config)
		}()

		ImagePipeline.disableSweep(for: tileCacheDirectory)
		
		let diskCache = try! DataCache(path: tileCacheDirectory, filenameGenerator: { $0 })
		diskCache.sizeLimit = 10 * 1024 * 1024 * 1024  // 10 GB
		diskCache.sweepInterval = 100 * 365 * 24 * 60 * 60   // never — will do it manually through settings
		
		ImageCache.shared.costLimit = 1024 * 1024 * 100 // 150 MB
		ImageCache.shared.countLimit = 100

		return ImagePipeline(delegate: self) {
			$0.dataLoader = dataLoader
			$0.dataCache = diskCache
			$0.dataLoadingQueue.maxConcurrentOperationCount = 6
		}
	}
	
	private func preheatCacheLookup() {
		DispatchQueue.global(qos: .background).async { [self] in
			let files = (try? FileManager.default.contentsOfDirectory(at: tileCacheDirectory, includingPropertiesForKeys: nil)) ?? []
			let tiles = files.compactMap {
				let components = $0.lastPathComponent.components(separatedBy: "_")
				if components.count == 3,
				   let x = Int(components[1]),
				   let y = Int(components[2]),
				   let z = Int(components[0]) {
					return MapTile(x: x, y: y, zoom: z, size: tileSize)
				} else {
					return nil
				}
			}
			
			DispatchQueue.main.async { [self] in
				for tile in tiles {
					Self.cachedImageLookup[self]?[tile] = true
				}
			}
		}
	}
	
	public func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
		let tile = request.userInfo[.tileKey] as! MapTile
		return "\(tile.zoom)_\(tile.x)_\(tile.y)"
	}
}

public extension ImageRequest.UserInfoKey {
	static let tileKey: ImageRequest.UserInfoKey = "tile"
	static let tileSourceIdKey: ImageRequest.UserInfoKey = "tileSourceId"
}

public extension ImagePipeline {
	static func disableSweep(for path: URL) {
		struct Metadata: Codable {
			var lastSweepDate: Date?
		}
		
		let metadata = Metadata(lastSweepDate: .distantFuture)
		let metadataFileURL = path.appendingPathComponent(".data-cache-info", isDirectory: false)
		try? JSONEncoder().encode(metadata).write(to: metadataFileURL)
	}
}
