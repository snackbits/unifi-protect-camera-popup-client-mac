// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ProtectKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ProtectKit", targets: ["ProtectKit"])
    ],
    targets: [
        .target(name: "ProtectKit"),
        .testTarget(
            name: "ProtectKitTests",
            dependencies: ["ProtectKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
