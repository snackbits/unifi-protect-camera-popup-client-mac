// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AppCore", targets: ["AppCore"])
    ],
    targets: [
        .target(name: "AppCore"),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"])
    ]
)
