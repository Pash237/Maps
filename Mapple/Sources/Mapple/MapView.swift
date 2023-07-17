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
			tileMapView.tileSources = tileSources
		}
	}
	
	public var onScroll = PassthroughSubject<ScrollReason, Never>()
	public var onTap = PassthroughSubject<Coordinates, Never>()
	public var onTapOnLayer = PassthroughSubject<AnyHashable, Never>()
	public var onLongPress = PassthroughSubject<Coordinates, Never>()
	public var onBeginTracking = PassthroughSubject<AnyHashable, Never>()
	public var onEndTracking = PassthroughSubject<AnyHashable, Never>()
	public var trackingLayer: AnyHashable?
	
	private let tileMapView = TileMapView()
	public let pointLayers = PointMapLayersView()
	public let spatialLayers = SpatialMapLayersView()
	
	public init(frame: CGRect, tileSources: [TileSource], camera: Camera) {
		self.tileSources = tileSources
		tileMapView.tileSources = tileSources
		super.init(frame: frame, camera: camera)
				
		tileMapView.frame = bounds
		tileMapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		addSubview(tileMapView)
		spatialLayers.frame = bounds
		spatialLayers.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		addSubview(spatialLayers)
		pointLayers.frame = bounds
		pointLayers.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		addSubview(pointLayers)
	}

	public convenience init(frame: CGRect, tileSource: TileSource, camera: Camera) {
		self.init(frame: frame, tileSources: [tileSource], camera: camera)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	private var tileSize: Int { tileSources[0].tileSize }
	
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
		
		spatialLayers.update(offset: offset, zoom: zoom, rotation: rotation)
		pointLayers.update(offset: offset, zoom: zoom, rotation: rotation)
		
		
		if !tileMapView.layer.bounds.isEmpty {
			tileMapView.layer.setAffineTransform(CGAffineTransform(rotationAngle: camera.rotation))
			spatialLayers.layer.setAffineTransform(CGAffineTransform(rotationAngle: camera.rotation))
			pointLayers.layer.setAffineTransform(CGAffineTransform(rotationAngle: camera.rotation))
		}
		
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
	
	override var mapContentsView: UIView {
		tileMapView
	}
	
	public func layerId(at coordinates: Coordinates) -> AnyHashable? {
		let touchedLayerIds = spatialLayers.layerIds(at: coordinates).map {
			(key: $0.key, distance: $0.distance)
		}
		+
		pointLayers.layerIds(at: coordinates).map {
			(key: $0.key, distance: $0.distance - 6.0)	// higher priority for POIs
		}
		
		let closest = touchedLayerIds.min(by: {
			$0.distance < $1.distance
		})
		
		return closest?.key
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
	
	override func trackingLayer(at point: CGPoint) -> AnyHashable? {
		layerId(at: coordinates(at: point))
	}
	
	override func onBeginTracking(_ trackingLayer: AnyHashable) {
		onBeginTracking.send(trackingLayer)
	}
	
	override func onEndTracking(_ trackingLayer: AnyHashable) {
		onEndTracking.send(trackingLayer)
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
