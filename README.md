<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS_16+-000000?style=for-the-badge&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/Swift-5.9+-F05138?style=for-the-badge&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/ARKit-LiDAR-0A84FF?style=for-the-badge&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" />
</p>

<h1 align="center">SpatialYOLO</h1>

<p align="center">
  <strong>Real-time 3D object detection that fuses YOLO with ARKit LiDAR depth</strong>
</p>

<p align="center">
  Drop-in SwiftUI view &middot; 2D → 3D lifting &middot; Persistent tracking with unique IDs &middot; SF-style AR overlay
</p>

<br/>

<!-- Replace with your own demo -->
<!-- <p align="center">
  <img src="docs/demo.gif" width="300" />
</p> -->

## What is SpatialYOLO?

SpatialYOLO is a Swift Package that bridges **2D object detection** and **3D spatial computing**. It takes YOLO detections from a camera frame, lifts them into 3D world coordinates using ARKit's LiDAR depth, and tracks each object across frames with persistent IDs and EMA-smoothed positions.

```
Camera Frame → YOLO 2D Detection → LiDAR Depth Sampling → 3D Position
     ↓                                                        ↓
  ARKit Scene ← Billboard Labels ← Lifecycle Tracking ← Back-Projection Match
```

## Features

- **2D → 3D Lifting** — Grid-based depth sampling with quality gates and 3D→2D consistency checks
- **Persistent Tracking** — Objects survive occlusion with candidate → confirmed → stale → lost lifecycle
- **Back-Projection Matching** — Two-stage IoU + center-distance matching prevents ID switches
- **3D Proximity Recapture** — Stale objects are recaptured when a new detection appears within 8 cm
- **EMA Smoothing** — Position, size, and confidence are smoothed to eliminate jitter
- **SF Scan Overlay** — Vision Pro glassmorphism-style corner brackets with depth-aware rendering
- **RealityKit Billboards** — 3D labels with class name + distance that scale with depth
- **Pluggable Detector** — Use the built-in `YOLODetector` or bring your own model via the `ObjectDetector` protocol
- **20+ Tunable Parameters** — Fine-tune depth sampling, matching, lifecycle, and rendering via `SpatialYOLOConfig`

## Quick Start

### Installation

Add SpatialYOLO via Swift Package Manager:

```
https://github.com/john-rocky/SpatialYOLO.git
```

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/john-rocky/SpatialYOLO.git", from: "1.0.0")
]
```

### Usage

**Mode A — Built-in Detector (simplest)**

```swift
import SpatialYOLO
import ARKit

let session = ARSession()
let detector = YOLODetector(modelName: "yolo11n")

try await detector.loadModel()

let pipeline = SpatialPipeline(session: session, detector: detector)

// In your ARSessionDelegate:
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    pipeline.update(frame: frame)
}
```

**Mode B — Bring Your Own Detections**

```swift
let pipeline = SpatialPipeline(session: session)

func session(_ session: ARSession, didUpdate frame: ARFrame) {
    let detections: [Detection2D] = myCustomDetector.run(frame)
    pipeline.update(frame: frame, detections: detections)
}
```

**SwiftUI View (one line)**

```swift
SpatialYOLOView(pipeline: pipeline, session: session)
    .ignoresSafeArea()
```

### Full Example

See [`Examples/SpatialYOLODemo`](Examples/SpatialYOLODemo) for a complete working app.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    SpatialPipeline                       │
│                                                         │
│  ┌──────────────┐    ┌───────────────────┐              │
│  │ YOLODetector │───▶│ Detection3DFactory│              │
│  │  (Mode A)    │    │                   │              │
│  └──────────────┘    │ • Grid depth      │              │
│         or           │ • Quality gates   │              │
│  ┌──────────────┐    │ • 3D→2D verify    │              │
│  │ External 2D  │───▶│ • Size estimation │              │
│  │  (Mode B)    │    └───────┬───────────┘              │
│  └──────────────┘            │                          │
│                              ▼                          │
│                  ┌───────────────────────┐              │
│                  │BackProjectionMatcher  │              │
│                  │ Stage 1: High IoU     │              │
│                  │ Stage 2: Composite    │              │
│                  └───────────┬───────────┘              │
│                              │                          │
│                              ▼                          │
│                  ┌───────────────────────┐              │
│                  │     SlotManager       │              │
│                  │ • EMA smoothing       │              │
│                  │ • Lifecycle states    │              │
│                  │ • 3D recapture        │              │
│                  └───────────┬───────────┘              │
│                              │                          │
│                              ▼                          │
│                    @Published trackedObjects             │
└─────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────┐
│                   SpatialYOLOView                        │
│  ┌─────────────────┐  ┌──────────────────────────────┐  │
│  │  ARViewContainer│  │      ScanOverlayView         │  │
│  │  (RealityKit)   │  │  SF bracket corners + glow   │  │
│  │  + Billboards   │  │  depth-aware front/back face │  │
│  └─────────────────┘  └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Configuration

```swift
var config = SpatialYOLOConfig()

// Detection
config.minDetectionConfidence = 0.35

// Depth sampling
config.depthGridRows = 3
config.depthGridCols = 6
config.minDepthQuality = 0.4

// Matching
config.highIoUThreshold = 0.75

// Lifecycle
config.confirmationFrames = 3
config.staleFrames = 15
config.lostFrames = 90
config.recaptureDistance = 0.08  // meters

let pipeline = SpatialPipeline(session: session, detector: detector, config: config)
```

## Object Lifecycle

```
  Detection
      │
      ▼
 ┌──────────┐  3 consecutive   ┌───────────┐
 │ Candidate │────frames───────▶│ Confirmed │◀─── Recapture
 └──────────┘                   └───────────┘        ▲
      │                              │               │
      │ missed                       │ 15 missed     │ within 8cm
      ▼                              ▼               │
   ┌──────┐                     ┌─────────┐          │
   │ Lost │                     │  Stale  │──────────┘
   └──────┘                     └─────────┘
                                     │ 90 missed
                                     ▼
                                 ┌──────┐
                                 │ Lost │
                                 └──────┘
```

## Requirements

| | Minimum |
|---|---|
| iOS | 16.0+ |
| Swift | 5.9+ |
| Hardware | LiDAR-equipped device (iPhone 12 Pro+, iPad Pro M1+) |
| Permissions | Camera |

## License

MIT License. See [LICENSE](LICENSE) for details.
