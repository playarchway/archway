// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Overcross",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OvercrossCore", targets: ["OvercrossCore"]),
        .executable(name: "overcross", targets: ["overcross"]),
        .executable(name: "OvercrossApp", targets: ["OvercrossApp"]),
    ],
    targets: [
        .target(name: "OvercrossCore", resources: [.copy("Resources/steamwebhelper-shim.exe")]),
        .executableTarget(name: "overcross", dependencies: ["OvercrossCore"]),
        .executableTarget(name: "OvercrossApp", dependencies: ["OvercrossCore"]),
        .testTarget(name: "OvercrossCoreTests", dependencies: ["OvercrossCore"]),
    ]
)
