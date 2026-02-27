// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpatialYOLO",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "SpatialYOLO",
            targets: ["SpatialYOLO"]
        ),
    ],
    targets: [
        .target(
            name: "SpatialYOLO",
            path: "Sources/SpatialYOLO"
        ),
    ]
)
