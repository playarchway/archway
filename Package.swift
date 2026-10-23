// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Overcross",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OvercrossCore", targets: ["OvercrossCore"]),
        .executable(name: "overcross", targets: ["overcross"]),
        .executable(name: "Archway", targets: ["Archway"]),
    ],
    targets: [
        .target(name: "OvercrossCore", resources: [.copy("Resources/steamwebhelper-shim.exe")]),
        .executableTarget(name: "overcross", dependencies: ["OvercrossCore"]),
        .executableTarget(name: "Archway", dependencies: ["OvercrossCore"], resources: [
            .copy("Resources/AppIcon.png"),
            .copy("Resources/AppIcon-Gateway.png"),
            .process("Resources/Localizable.xcstrings"),
        ]),
        .testTarget(name: "OvercrossCoreTests", dependencies: ["OvercrossCore"]),
    ]
)
