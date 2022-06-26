//
//  ViewController.swift
//  Example
//
//  Created by Pavel Alexeev on 09.06.2022.
//

import UIKit
import Mapple

class ViewController: UIViewController {
	override func viewDidLoad() {
		super.viewDidLoad()
		
		let camera = Camera(center: Coordinates(latitude: 37.322621, longitude: -122.031945), zoom: 14)
		let mapView = RasterMapView(frame: view.bounds, tileSources: [
			TileSource(title: "OpenStreetMap", url: "https://tile.openstreetmap.org/{z}/{x}/{y}.png"),
			TileSource(title: "OpenStreetMap Traces", url: "https://gps-a.tile.openstreetmap.org/lines/{z}/{x}/{y}.png")
		], camera: camera)
		mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		view.addSubview(mapView)
		
		
		// draw track
		let track = [
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
		
		mapView.addMapLayer {layer in
			let layer = layer as? CAShapeLayer ?? CAShapeLayer()
			let linePath = UIBezierPath()
			
			for (i, coordinates) in track.enumerated() {
				let point = mapView.point(at: coordinates)
				if i == 0 {
					linePath.move(to: point)
				} else {
					linePath.addLine(to: point)
				}
			}
			
			layer.path = linePath.cgPath
			layer.opacity = 1
			layer.lineWidth = 3
			layer.lineCap = .round
			layer.lineJoin = .round
			layer.fillColor = UIColor.clear.cgColor
			layer.strokeColor = UIColor.systemRed.cgColor
			
			return layer
		}
		
		// draw marker
		let start = Coordinates(37.322830, -122.032186)
		
		mapView.addMapLayer {layer in
			let layer = layer ?? CALayer()
			let imageLayer = layer.sublayers?.first ?? CALayer()
			let size = CGSize(width: 34, height: 34)
			imageLayer.frame = CGRect(origin: mapView.point(at: start) - size/2,
									  size: size)
			imageLayer.contents = UIImage(systemName: "heart.circle")?.cgImage
			layer.addSublayer(imageLayer)
			
			return layer
		}
	}
}

