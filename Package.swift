// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Overcross",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "OvercrossCore", targets: ["OvercrossCore"]),
        .executable(name: "overcross", targets: ["overcross"]),
    ],
    targets: [
        .target(name: "OvercrossCore", resources: [.copy("Resources/steamwebhelper-shim.exe")]),
        .executableTarget(name: "overcross", dependencies: ["OvercrossCore"]),
        .testTarget(name: "OvercrossCoreTests", dependencies: ["OvercrossCore"]),
    ]
)
