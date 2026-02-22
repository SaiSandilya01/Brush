// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Brush",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Brush", targets: ["Brush"])
    ],
    targets: [
        .executableTarget(
            name: "Brush",
            path: "Sources/Brush"
        )
    ]
)
