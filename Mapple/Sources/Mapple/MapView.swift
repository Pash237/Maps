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

public struct ScrollChange {
	public var translation: Point
	public var zoom: Double
	public var rotation: Radians
	
	public static let zero = ScrollChange(translation: .zero, zoom: 0, rotation: 0)
}

public protocol MapViewLayer: UIView {
	func update(offset: Point, zoom: Double, rotation: Radians)
}

public protocol TouchableMapViewLayer {
	func layerIds(at coordinates: Coordinates, threshold: CGFloat) -> [(key: AnyHashable, distance: CGFloat)]
}

extension TouchableMapViewLayer {
	public func layerId(at coordinates: Coordinates) -> AnyHashable? {
		let touchedLayerIds = layerIds(at: coordinates, threshold: 30).map {
			(key: $0.key, distance: $0.distance)
		}

		let closest = touchedLayerIds.min(by: {
			$0.distance < $1.distance
		})
		
		return closest?.key
	}
}

public class MapView: MapScrollView {
	private var tileLayersCache: [TileSource: [MapTile: MapTileLayer]] = [:]
	
	public var tileSources: [TileSource] {
		didSet {
			tileMapView.tileSources = tileSources
		}
	}
	
	public var onScroll = PassthroughSubject<(reason: ScrollReason, change: ScrollChange), Never>()
	public var onTap = PassthroughSubject<Coordinates, Never>()
	public var onTapOnLayer = PassthroughSubject<AnyHashable, Never>()
	public var onLongPress = PassthroughSubject<Coordinates, Never>()
	public var onMoveLongPress = PassthroughSubject<Coordinates, Never>()
	public var onEndLongPress = PassthroughSubject<Coordinates, Never>()
	public var onBeginTracking = PassthroughSubject<AnyHashable, Never>()
	public var onEndTracking = PassthroughSubject<AnyHashable, Never>()
	public var trackingLayer: AnyHashable?
	
	public var draggingLayer: AnyHashable?
	public var shouldStartDraggingLayer: ((AnyHashable, Coordinates) -> (AnyHashable?))?
	public var onDragLayer: ((AnyHashable, Coordinates) -> ())?
	public var onEndDraggingLayer: ((AnyHashable, Coordinates) -> ())?
	
	private var mapLayers: [MapViewLayer]
	
	private let tileMapView = TileMapView()
	public let spatialLayers = SpatialMapLayersView()
	public let pointLayers = PointMapLayersView()
	public let topSpatialLayers = SpatialMapLayersView()
	
	public init(frame: CGRect, tileSources: [TileSource], camera: Camera) {
		self.tileSources = tileSources
		tileMapView.tileSources = tileSources
		
		mapLayers = [
			tileMapView,
			spatialLayers,
			pointLayers,
			topSpatialLayers
		]
		mapLayers.forEach {
			$0.frame = CGRect(origin: .zero, size: frame.size)
		}
		
		super.init(frame: frame, camera: camera)
		
		mapLayers.forEach {
			addSubview($0)
		}
	}

	public convenience init(frame: CGRect, tileSource: TileSource, camera: Camera) {
		self.init(frame: frame, tileSources: [tileSource], camera: camera)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	private var tileSize: Int { tileSources[0].tileSize }
	
	override func updateOffset(to camera: Camera, reason: ScrollReason) {
		super.updateOffset(to: camera, reason: reason)
	}
	
	override func didScroll(reason: ScrollReason, change: ScrollChange) {
		super.didScroll(reason: reason, change: change)
		
		let minZoom = (UIScreen.main.bounds.height/2 + 100.0) / Double(tileSize)
		if zoom < minZoom {
			zoom = minZoom
		}
		if zoom > 25 {
			zoom = 25
		}
		
		if offset.y < 0 {
			offset.y = 0
		}
		if offset.y > mapWidth - bounds.height {
			offset.y = mapWidth - bounds.height
		}
		
		updateLayers()
		onScroll.send((reason: reason, change: change))
	}
	
	private var mapWidth: Double {
		Double(tileSize) * pow(2, zoom)
	}
	
	private func updateLayers() {
		guard !tileMapView.layer.bounds.isEmpty else {
			return
		}
		
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		
		//TODO: do not update if nothing's changed!
		
		mapLayers.forEach {
			$0.update(offset: offset, zoom: zoom, rotation: rotation)
			let center = contentBounds.center - center
			var transform = CGAffineTransformMakeTranslation(center.x, center.y);
			transform = CGAffineTransformRotate(transform, rotation);
			transform = CGAffineTransformTranslate(transform, -center.x, -center.y);
			$0.transform = transform
		}
		
		CATransaction.commit()
	}
	
	public func addMapViewLayer(_ layer: MapViewLayer) {
		mapLayers.append(layer)
		addSubview(layer)
		updateLayers()
	}
	
	public func addMapViewLayer(_ layer: MapViewLayer, below: MapViewLayer) {
		guard let index = mapLayers.firstIndex(where: {$0 === below}) else {
			assertionFailure("Layer not found")
			addMapViewLayer(layer)
			return
		}
		mapLayers.insert(layer, at: index)
		insertSubview(layer, at: index)
		updateLayers()
	}
	
	public func removeMapViewLayer(_ layer: MapViewLayer) {
		if let index = mapLayers.firstIndex(where: { $0 === layer }) {
			mapLayers.remove(at: index)
			layer.removeFromSuperview()
		}
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
		
		if bounds != oldBounds {
			mapLayers.forEach {
				$0.transform = .identity
				$0.frame = bounds
			}
			
			updateLayers()
			onScroll.send((reason: .layoutChange, change: ScrollChange(translation: .zero, zoom: 0, rotation: 0)))
			
			oldBounds = bounds
		}
	}
	
	override var mapContentsView: UIView {
		tileMapView
	}
	
	public func layerId(at coordinates: Coordinates) -> AnyHashable? {
		let touchedLayerIds = mapLayers.compactMap({ $0 as? TouchableMapViewLayer & MapViewLayer }).reduce([], { result, layer in
			result + layer.layerIds(at: coordinates, threshold: 30).map {
				(key: $0.key, distance: $0.distance - (layer === pointLayers ? 6.0 : 0))
			}
		})

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
	
	override func onMoveLongPress(point: CGPoint) {
		let coordinates = coordinates(at: point)
		onMoveLongPress.send(coordinates)
	}
	
	override func onEndLongPress(point: CGPoint) {
		let coordinates = coordinates(at: point)
		onEndLongPress.send(coordinates)
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
	
	private var dragLayerOffset: CGPoint = .zero
	override func shouldStartDragging(_ layerId: AnyHashable, at point: CGPoint) -> AnyHashable? {
		if let layerPosition = pointLayers.mapLayer(with: layerId)?.position {
			// TODO: doesn't work for waypoints :(
			dragLayerOffset = layerPosition - point
		} else {
			dragLayerOffset = .zero
		}
		return shouldStartDraggingLayer?(layerId, coordinates(at: point)) ?? nil
	}
	
	override func didDragLayer(_ layerId: AnyHashable, to point: CGPoint) {
		let coordinates = coordinates(at: point + dragLayerOffset)
		onDragLayer?(layerId, coordinates)
	}
	
	override func didEndDraggingLayer(_ layerId: AnyHashable, at point: CGPoint) {
		let coordinates = coordinates(at: point + dragLayerOffset)
		onEndDraggingLayer?(layerId, coordinates)
	}
}


//-------------------


final class Logger {
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
