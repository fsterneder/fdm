// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "fdm",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "fdm", targets: ["Metronom"])],
    targets: [
        .target(name: "TempoCore"),
        .target(name: "RealtimeAudio", publicHeadersPath: "include"),
        .executableTarget(name: "Metronom", dependencies: ["TempoCore", "RealtimeAudio"]),
        .testTarget(name: "TempoCoreTests", dependencies: ["TempoCore"])
    ],
    cLanguageStandard: .c11
)

