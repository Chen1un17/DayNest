// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DayNest",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DayNest", targets: ["DayNest"])],
    targets: [
        .executableTarget(name: "DayNest")
    ]
)
