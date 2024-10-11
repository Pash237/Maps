Raster map library with support for tile map sources.  

All standard gestures are supported:
- Dragging.
- Pinch to zoom.
- Single finger double-tap to zoom in.
- Two finger double-tap to zoom out.
- Tap-tap-drag to zoom.

Usage:
```swift
let camera = Camera(center: Coordinates(latitude: 37.322621, longitude: -122.031945), zoom: 14)
let tileSource = TileSource(title: "OpenStreetMap", url: "https://tile.openstreetmap.org/{z}/{x}/{y}.png")
let mapView = MapView(frame: view.bounds, tileSources: [tileSource], camera: camera)
view.addSubview(mapView)
```

See Example for more uses.
