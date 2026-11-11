// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "fdm-3",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "fdm-3", targets: ["Metronom"])],
    targets: [
        .target(name: "TempoCore"),
        .executableTarget(name: "Metronom", dependencies: ["TempoCore"]),
        .testTarget(name: "TempoCoreTests", dependencies: ["TempoCore"])
    ]
)
