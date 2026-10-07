// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CarCareCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CarCareCore", targets: ["CarCareCore"])
    ],
    targets: [
        .target(name: "CarCareCore"),
        .testTarget(name: "CarCareCoreTests", dependencies: ["CarCareCore"])
    ]
)
