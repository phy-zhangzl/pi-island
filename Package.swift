// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PiIsland",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PiIsland", targets: ["PiIsland"])
    ],
    targets: [
        .executableTarget(
            name: "PiIsland",
            path: "Sources"
        )
    ]
)
