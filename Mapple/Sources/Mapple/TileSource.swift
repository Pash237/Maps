//
//  TileSource.swift
//  maps
//
//  Created by Pavel Alexeev on 09.06.2022.
//

import Foundation
import UIKit
import Nuke

public final class TileSource: Equatable, Hashable, ImagePipelineDelegate, @unchecked Sendable {
	public let title: String
	public let url: String
	public let tileSize: Int	//size in points on screen
	public let minZoom: Int
	public let maxZoom: Int
	public let headers: [String:String]
	
	private var imagePipeline: ImagePipeline!
	public let hash: Int
	public let stringHash: String
	
	private static var cachedImageLookup: [TileSource:[MapTile:Bool]] = [:]

	public init(title: String, url: String, tileSize: Int = 256, minZoom: Int = 1, maxZoom: Int = 20, headers: [String:String] = [:], imagePipeline: ImagePipeline? = nil) {
		self.title = title
		self.url = url
		self.headers = headers
		self.tileSize = tileSize
		self.minZoom = minZoom
		self.maxZoom = maxZoom
		self.hash = abs(url.hash)
		self.stringHash = String(hash % 1679616, radix: 36)
		self.imagePipeline = imagePipeline ?? defaultImagePipeline()
		
		if Self.cachedImageLookup[self] == nil {
			Self.cachedImageLookup[self] = [:]
			preheatCacheLookup()
		}
	}
	
	public init(title: String, url: String, tileSize: Int = 256, minZoom: Int = 1, maxZoom: Int = 20, headers: [String:String] = [:], ttl: TimeInterval) {
		self.title = title
		self.url = url
		self.headers = headers
		self.tileSize = tileSize
		self.minZoom = minZoom
		self.maxZoom = maxZoom
		self.hash = abs(url.hash)
		self.stringHash = String(hash % 1679616, radix: 36)
		self.imagePipeline = noCacheImagePipeline(ttl: ttl)
		
		if Self.cachedImageLookup[self] == nil {
			Self.cachedImageLookup[self] = [:]
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
	
	@discardableResult
	public func loadImage(for tile: MapTile, completion: @escaping ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)) -> ImageTask {
		let url = url(for: tile)
		var urlRequest = URLRequest(url: url)
		for (key, value) in headers {
			urlRequest.setValue(value, forHTTPHeaderField: key)
		}
		var request = ImageRequest(urlRequest: urlRequest)
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
	
	public lazy var tileCacheDirectory: URL = {
		FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
			.appendingPathComponent("TileCache", isDirectory: true)
			.appendingPathComponent(title, isDirectory: true)
	}()
	
	private func defaultImagePipeline() -> ImagePipeline {
		let dataLoader: DataLoader = {
			let config = URLSessionConfiguration.default
			config.urlCache = nil
			config.waitsForConnectivity = true
			return DataLoader(configuration: config)
		}()

		ImagePipeline.disableSweep(for: tileCacheDirectory)
		
		tileCacheDirectory.excludeFromBackup()
		
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
	
	func noCacheImagePipeline(ttl: TimeInterval) -> ImagePipeline {
		let dataLoader: DataLoader = {
			let config = URLSessionConfiguration.default
			config.urlCache = nil
			config.waitsForConnectivity = true
			return DataLoader(configuration: config)
		}()
		
		let imageCache = ImageCache()
		imageCache.ttl = ttl
		
		return ImagePipeline(delegate: self) {
			$0.dataLoader = dataLoader
			$0.dataCache = nil
			$0.dataLoadingQueue.maxConcurrentOperationCount = 6
			$0.imageCache = imageCache
		}
	}
	
	
	private func preheatCacheLookup() {
		DispatchQueue.global(qos: .background).async { [self] in
			
			guard let path = tileCacheDirectory.path.cString(using: String.Encoding.utf8) else { return }
			guard let dir = opendir(path) else { return }
			
			var tiles: [MapTile] = []
			
			// many times faster than using FileManager.contentsOfDirectory and String.components(separatedBy)
			while let entry = readdir(dir) {
				let nameLength = Int(entry.pointee.d_namlen)
				withUnsafePointer(to: &entry.pointee.d_name) {
					$0.withMemoryRebound(to: CChar.self, capacity: nameLength) { filename in
						var numbers: [Int] = [0, 0, 0]
						var current: Int = -1
						var i = 0
						var c: Int8 = 0
						repeat {
							c = filename[i]
							if c == 0x5F || c == 0 {	// '_'
								current += 1
								if current >= 3 { break }
							} else if current >= 0 {
								// parse string to int
								numbers[current] = numbers[current] * 10 + (Int(c) - 0x30)	// '0'
							}
							i += 1
						} while c != 0
						
						if current == 3 {
							tiles.append(MapTile(x: numbers[1], y: numbers[2], zoom: numbers[0], size: tileSize))
						}
					}
				}
			}
			
			closedir(dir);
			
			DispatchQueue.main.async { [self] in
				for tile in tiles {
					Self.cachedImageLookup[self]?[tile] = true
				}
			}
		}
	}
	
	public var zoomRange: ClosedRange<Int> {
		let minZoom = minZoom
		let maxZoom = maxZoom
		guard maxZoom >= minZoom else {
			return maxZoom...maxZoom
		}
		return minZoom...maxZoom
	}
	
	public func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
		let tile = request.userInfo[.tileKey] as! MapTile
		return "\(stringHash)_\(tile.zoom)_\(tile.x)_\(tile.y)"
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

private extension URL {
	mutating func excludeFromBackup() {
		var values = URLResourceValues()
		values.isExcludedFromBackup = true
		do {
			if !FileManager.default.fileExists(atPath: path) {
				try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
			}
			try self.setResourceValues(values)
		} catch {
			assertionFailure("Unable to exclude \(self) from backup")
		}
	}
}
