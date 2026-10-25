// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Archway",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArchwayCore", targets: ["ArchwayCore"]),
        .executable(name: "archway", targets: ["ArchwayCLI"]),
        .executable(name: "ArchwayApp", targets: ["Archway"]),
    ],
    targets: [
        .target(name: "ArchwayCore", resources: [
            .copy("Resources/steamwebhelper-shim.exe"),
            .copy("Resources/runtime.json"),
        ]),
        .executableTarget(name: "ArchwayCLI", dependencies: ["ArchwayCore"]),
        .executableTarget(name: "Archway", dependencies: ["ArchwayCore"], resources: [
            .copy("Resources/AppIcon.png"),
            .copy("Resources/AppIcon-Gateway.png"),
            .copy("Resources/DefaultBackdrop.jpg"),
            .process("Resources/Localizable.xcstrings"),
        ]),
        .testTarget(name: "ArchwayCoreTests", dependencies: ["ArchwayCore"]),
    ]
)
