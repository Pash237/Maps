//
//  ViewController.swift
//  Example
//
//  Created by Pavel Alexeev on 09.06.2022.
//

import UIKit
import Combine
import Mapple

class ViewController: UIViewController {


	// draw track
	private let track = [
		Coordinates(37.322830, -122.032186),
		Coordinates(37.322853, -122.023205),
		Coordinates(37.331860, -122.023233),
		Coordinates(37.333116, -122.023643),
		Coordinates(37.335326, -122.023587),
		Coordinates(37.336419, -122.023293),
		Coordinates(37.337669, -122.023326),
		Coordinates(37.337756, -122.005407),
		Coordinates(37.335864, -122.005407),
		Coordinates(37.335873, -122.006310),
	]
	var pointCoordinates = Coordinates(37.322830, -122.032186)
	
	private var cancellable = Set<AnyCancellable>()

	override func viewDidLoad() {
		super.viewDidLoad()

		let camera = Camera(center: Coordinates(latitude: 37.322621, longitude: -122.031945), zoom: 14)
		let tileSource = TileSource(title: "OpenStreetMap", url: "https://tile.openstreetmap.org/{z}/{x}/{y}.png")
		let mapView = MapView(frame: view.bounds, tileSource: tileSource, camera: camera)
		mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		view.addSubview(mapView)

		mapView.spatialLayers.addMapLayer { [unowned self] layer in
			let layer = layer as? CAShapeLayer ?? CAShapeLayer()
			let linePath = UIBezierPath()

			var lastPoint: Point = .zero
			for i in 0..<track.count {
				let coordinates = track[i]
				let point = mapView.point(at: coordinates)
				if i == 0 {
					linePath.move(to: point)
				} else if (lastPoint - point).maxDimension > 5 {
					linePath.addLine(to: point)
					lastPoint = point
				}
			}

			layer.path = linePath.cgPath
			layer.lineWidth = 3
			layer.fillColor = UIColor.clear.cgColor
			layer.strokeColor = UIColor.systemRed.cgColor

			return layer
		}

		// draw marker
		mapView.pointLayers.addMapLayer(id: "heart") { [unowned self] reuseLayer in
			let layer: PointMapLayer
			if let reuseLayer {
				layer = reuseLayer
				layer.coordinates = pointCoordinates
			} else {
				layer = PointMapLayer(coordinates: pointCoordinates)
				layer.frame = CGRect(x: 0, y: 0, width: 34, height: 34)
				layer.contents = UIImage(systemName: "heart.circle")?.cgImage
			}

			return layer
		}
		
		// move marker to the tapped point on the map
		mapView.onTap.sink { [unowned self] coordinates in
			pointCoordinates = coordinates
			mapView.pointLayers.redrawLayer(id: "heart")
		}.store(in: &cancellable)
	}
}

