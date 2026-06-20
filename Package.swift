// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KnowledgeKit",
    platforms: [.macOS(.v12), .iOS(.v15), .tvOS(.v15), .visionOS(.v1)],
    products: [
        .library(name: "KnowledgeKit", targets: ["KnowledgeKit"]),
    ],
    targets: [
        .target(name: "KnowledgeKit"),
        .testTarget(name: "KnowledgeKitTests", dependencies: ["KnowledgeKit"]),
    ]
)
