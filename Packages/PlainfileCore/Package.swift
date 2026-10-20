// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlainfileCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PlainfileCore", targets: ["PlainfileCore"])
    ],
    targets: [
        .target(name: "PlainfileCore"),
        .testTarget(name: "PlainfileCoreTests", dependencies: ["PlainfileCore"]),
    ]
)
