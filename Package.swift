// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MenuShelf",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MenuShelf", targets: ["MenuShelf"])],
    targets: [
        .executableTarget(name: "MenuShelf"),
        .testTarget(name: "MenuShelfTests", dependencies: ["MenuShelf"])
    ]
)
