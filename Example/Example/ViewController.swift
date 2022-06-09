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
		
		let tileSource = TileSource(title: "OpenStreetMap", url: "https://tile.openstreetmap.org/{z}/{x}/{y}.png")
		
		let mapView = RasterMapView(frame: view.bounds, tileSource: tileSource)
		mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		view.addSubview(mapView)
		
		mapView.camera = Camera(center: Coordinates(latitude: 37.322621, longitude: -122.031945), zoom: 14)
	}
}

