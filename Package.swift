// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Tack",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tack", targets: ["Tack"]),
    ],
    targets: [
        .target(name: "TackKit", path: "Sources/TackKit"),
        .executableTarget(name: "Tack", dependencies: ["TackKit"], path: "Sources/Tack"),
        .testTarget(name: "TackKitTests", dependencies: ["TackKit"], path: "Tests/TackKitTests"),
    ]
)
