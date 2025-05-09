//
//  TileSource.swift
//  maps
//
//  Created by Pavel Alexeev on 09.06.2022.
//

import Foundation
import UIKit
import Nuke

public final class TileSource: Equatable, Hashable {
	public let title: String
	public let url: String
	public let tileSize: Int	//size in points on screen
	public let minZoom: Int
	public let maxZoom: Int
	public let headers: [String:String]
	public var thumbnailUrl: String?
	public var attribution: String?
	public var opacity: Float = 1
	public var useCase: UseCase = .baseLayer
	
	private lazy var imagePipeline: ImagePipeline = {
		preheatCacheLookup()
		return if let ttl { noCacheImagePipeline(ttl: ttl) } else { defaultImagePipeline() }
	}()
	
	public let hash: Int
	public let stringHash: String
	public let ttl: TimeInterval?
	public let urls: [Int: String]?
	public let projection: Projection?
	
	private var cachedImageLookup: [MapTile:Bool] = [:]
	
	public enum UseCase: Codable {
		case baseLayer
		case overlay
	}

	public init(title: String, url: String, urls: [ClosedRange<Int>: String]? = nil, tileSize: Int = 256, minZoom: Int = 1, maxZoom: Int = 20, opacity: Float = 1.0, useCase: UseCase = .baseLayer, headers: [String:String] = [:], ttl: TimeInterval? = nil, thumbnailUrl: String? = nil, attribution: String? = nil, projection: Projection? = nil) {
		self.title = title
		self.url = url
		self.headers = headers
		self.tileSize = tileSize
		self.opacity = opacity
		self.useCase = useCase
		self.minZoom = minZoom
		self.maxZoom = maxZoom
		self.hash = url.fnv1aHash
		self.stringHash = String(abs(hash) % 1679616, radix: 36)
		self.ttl = ttl
		self.thumbnailUrl = thumbnailUrl
		self.attribution = attribution
		if let urls {
			var perZoomUrls: [Int: String] = [:]
			for zoom in minZoom...maxZoom {
				perZoomUrls[zoom] = urls.first { $0.key.contains(zoom) }?.value
			}
			self.urls = perZoomUrls
		} else {
			self.urls = nil
		}
		self.projection = projection
	}

	public func url(for tile: MapTile) -> URL {
		let url = if let urls {
			urls[tile.zoom] ?? url
		} else {
			url
		}
		return URL(string: url
			.replacingMultipleOccurrences([
				"{x}": "\(tile.x)",
				"{y}": "\(tile.y)",
				"{z}": "\(tile.zoom)",
				"{$x}": "\(tile.x)",
				"{$y}": "\(tile.y)",
				"{$z}": "\(tile.zoom)",
				"{TileCol}": "\(tile.x)",
				"{TileRow}": "\(tile.y)",
				"{TileMatrix}": "\(tile.zoom)",
				"{zoom}": "\(tile.zoom)",
				"{ratio}": UIScreen.main.scale > 1 ? "@2x" : "",
				"{server}": ["a", "b", "c"][abs(tile.x + tile.y + tile.zoom) % 3],
				"{abc}": ["a", "b", "c"][abs(tile.x + tile.y + tile.zoom) % 3],
				"{abcd}": ["a", "b", "c", "d"][abs(tile.x + tile.y + tile.zoom) % 4],
				"{012}": ["0", "1", "2"][abs(tile.x + tile.y + tile.zoom) % 3],
				"{0123}": ["0", "1", "2", "3"][abs(tile.x + tile.y + tile.zoom) % 4],
				"{123}": ["1", "2", "3"][abs(tile.x + tile.y + tile.zoom) % 3],
				"{1234}": ["1", "2", "3", "4"][abs(tile.x + tile.y + tile.zoom) % 4],
				"{hash}": ((tile.x % 4) + (tile.y % 4) * 4).description
			])
					  
//			.replacingOccurrences(of: "{x}", with: "\(tile.x)")
//			.replacingOccurrences(of: "{y}", with: "\(tile.y)")
//			.replacingOccurrences(of: "{z}", with: "\(tile.zoom)")
//			.replacingOccurrences(of: "{$x}", with: "\(tile.x)")
//			.replacingOccurrences(of: "{$y}", with: "\(tile.y)")
//			.replacingOccurrences(of: "{$z}", with: "\(tile.zoom)")
//			.replacingOccurrences(of: "{TileRow}", with: "\(tile.x)")
//			.replacingOccurrences(of: "{TileCol}", with: "\(tile.y)")
//			.replacingOccurrences(of: "{TileMatrix}", with: "\(tile.zoom)")
//			.replacingOccurrences(of: "{zoom}", with: "\(tile.zoom)")
//			.replacingOccurrences(of: "{ratio}", with: UIScreen.main.scale > 1 ? "@2x" : "")
//			.replacingOccurrences(of: "{server}", with: ["a", "b", "c"][abs(tile.x + tile.y + tile.zoom) % 3])
//			.replacingOccurrences(of: "{abc}", with: ["a", "b", "c"][abs(tile.x + tile.y + tile.zoom) % 3])
//			.replacingOccurrences(of: "{abcd}", with: ["a", "b", "c", "d"][abs(tile.x + tile.y + tile.zoom) % 4])
//			.replacingOccurrences(of: "{012}", with: ["0", "1", "2"][abs(tile.x + tile.y + tile.zoom) % 3])
//			.replacingOccurrences(of: "{0123}", with: ["0", "1", "2", "3"][abs(tile.x + tile.y + tile.zoom) % 4])
//			.replacingOccurrences(of: "{123}", with: ["1", "2", "3"][abs(tile.x + tile.y + tile.zoom) % 3])
//			.replacingOccurrences(of: "{1234}", with: ["1", "2", "3", "4"][abs(tile.x + tile.y + tile.zoom) % 4])
//			.replacingOccurrences(of: "{hash}", with: ((tile.x % 4) + (tile.y % 4) * 4).description)
			//TODO: support {switch:a,b,c} and [abc]
			//TODO: support date formats
			//TODO: support {c} (for example, virtualearth.net)
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
		return imagePipeline.loadImage(with: request, completion: { [weak self] result in
			if case .success = result {
				self?.cachedImageLookup[tile] = true
			}
			completion(result)
		})
	}
	
	public func possiblyHasCachedImage(for tile: MapTile) -> Bool {
		cachedImageLookup[tile] ?? false
	}
	
	public func possiblyCachedTiles(for zoom: Int) -> [MapTile] {
		cachedImageLookup.keys.filter {
			$0.zoom == zoom
		}
	}
	
	public func hasCachedImage(for tile: MapTile) -> Bool {
		if let cached = cachedImageLookup[tile] {
			return cached
		}
		
		let url = url(for: tile)
		var request = ImageRequest(url: url)
		request.userInfo = [
			.tileKey: tile,
			.tileSourceIdKey: hash
		]
		let contains = imagePipeline.cache.containsCachedImage(for: request)
		cachedImageLookup[tile] = contains
		return contains
	}
	
	public func cachedImage(for tile: MapTile) -> CGImage? {
		let url = url(for: tile)
		var request = ImageRequest(url: url)
		request.userInfo = [
			.tileKey: tile,
			.tileSourceIdKey: hash
		]
		return imagePipeline.cache.cachedImage(for: request)?.image.cgImage
	}
	
	public static func == (lhs: TileSource, rhs: TileSource) -> Bool {
		lhs.hash == rhs.hash
	}
	
	public lazy var tileCacheDirectory: URL = {
		FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
			.appendingPathComponent("TileCache", isDirectory: true)
			.appendingPathComponent(title.filenameCompatible, isDirectory: true)
	}()
	
	private func defaultImagePipeline() -> ImagePipeline {
		ImagePipeline.disableSweep(for: tileCacheDirectory)
		
		tileCacheDirectory.excludeFromBackup()
		
		let diskCache = try! DataCache(path: tileCacheDirectory, filenameGenerator: { $0 })
		diskCache.sizeLimit = 10 * 1024 * 1024 * 1024  // 10 GB
		diskCache.sweepInterval = 100 * 365 * 24 * 60 * 60   // never — will do it manually through settings
		
		ImageCache.shared.costLimit = 1024 * 1024 * 100 // 150 MB
		ImageCache.shared.countLimit = 100

		return ImagePipeline(delegate: TileSourceImagePipelineDelegate(stringHash: stringHash)) {
			$0.dataLoader = DataLoader(configuration: .defaultForTileSource)
			$0.dataCache = diskCache
			$0.dataLoadingQueue.maxConcurrentOperationCount = 6
		}
	}
	
	func noCacheImagePipeline(ttl: TimeInterval) -> ImagePipeline {
		let imageCache = ImageCache()
		imageCache.ttl = ttl
		
		return ImagePipeline(delegate: TileSourceImagePipelineDelegate(stringHash: stringHash)) {
			$0.dataLoader = DataLoader(configuration: .defaultForTileSource)
			$0.dataCache = nil
			$0.dataLoadingQueue.maxConcurrentOperationCount = 6
			$0.imageCache = imageCache
		}
	}
	
	private func preheatCacheLookup() {
		DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 0.5) { [self] in
			
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
			
			for i in stride(from: 0, to: tiles.count, by: 1000) {
				DispatchQueue.main.asyncAfter(deadline: .now() + Double(i)*0.04) { [self] in
					for tile in tiles[i ..< min(i + 1000, tiles.count)] {
						cachedImageLookup[tile] = true
					}
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
}

private class TileSourceImagePipelineDelegate: ImagePipelineDelegate, @unchecked Sendable {
	let stringHash: String
	
	init(stringHash: String) {
		self.stringHash = stringHash
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

private extension URLSessionConfiguration {
	static let defaultForTileSource: URLSessionConfiguration = {
		let config = URLSessionConfiguration.default
		config.urlCache = nil
		config.waitsForConnectivity = true
		return config
	}()
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

public extension String {
	func replacingMultipleOccurrences(_ replacements: [String:String]) -> String {
		let count = count
		let maximumLength = count * 2
		let result = withCString { cString in
			let storage = UnsafeMutablePointer<CChar>.allocate(capacity: maximumLength)
			memset(storage, 0, maximumLength)
			memcpy(storage, cString, count)
			let temp = UnsafeMutablePointer<CChar>.allocate(capacity: maximumLength)
			
			for (old, new) in replacements {
				if let foundPosition = strstr(storage, old) {
					memcpy(temp, storage, maximumLength)
					let index = Int(bitPattern: foundPosition) - Int(bitPattern: storage)
					storage[index] = 0
					strcat(storage, new)
					strcat(storage, temp.advanced(by: index + old.count))
				}
			}
			
			return storage
		}
		
		// TODO: memory leak!
		
		let resultString = String(cString: result)
		return resultString
	}

	var fnv1aHash: Int {
		var hash: UInt64 = 14695981039346656037
		for byte in utf8 {
			hash ^= UInt64(byte)
			hash = hash &* UInt64(1099511628211)
		}
		return Int(truncatingIfNeeded: hash)
	}
}

extension TileSource: Codable {
	enum CodingKeys: String, CodingKey {
		case title
		case url
		case tileSize
		case minZoom
		case maxZoom
		case headers
		case thumbnailUrl
		case attribution
		case opacity
		case useCase
		case ttl
	}
	
	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(title, forKey: .title)
		try container.encode(url, forKey: .url)
		try container.encode(tileSize, forKey: .tileSize)
		try container.encode(minZoom, forKey: .minZoom)
		try container.encode(maxZoom, forKey: .maxZoom)
		try container.encode(headers, forKey: .headers)
		try container.encode(thumbnailUrl, forKey: .thumbnailUrl)
		try container.encode(attribution, forKey: .attribution)
		try container.encode(opacity, forKey: .opacity)
		try container.encode(useCase, forKey: .useCase)
		try container.encode(ttl, forKey: .ttl)
	}
	
	public convenience init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			title: try container.decode(String.self, forKey: .title),
			url: try container.decode(String.self, forKey: .url),
			tileSize: try container.decode(Int.self, forKey: .tileSize),
			minZoom: try container.decode(Int.self, forKey: .minZoom),
			maxZoom: try container.decode(Int.self, forKey: .maxZoom),
			opacity: try container.decode(Float.self, forKey: .opacity),
			useCase: try container.decode(UseCase.self, forKey: .useCase),
			headers: try container.decode([String: String].self, forKey: .headers),
			ttl: try container.decodeIfPresent(Double?.self, forKey: .ttl) ?? nil,
			thumbnailUrl: try container.decodeIfPresent(String?.self, forKey: .thumbnailUrl) ?? nil,
			attribution: try container.decodeIfPresent(String?.self, forKey: .attribution) ?? nil
		)
	}
}

extension String {
	var filenameCompatible: String {
		let invalidCharsets = CharacterSet(charactersIn: "?*|:/\\")
			.union(.illegalCharacters)
			.union(.controlCharacters)
			.union(.symbols)
			.union(.newlines)
		return components(separatedBy: invalidCharsets).joined(separator: "-")
	}
}
