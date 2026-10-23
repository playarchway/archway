import Foundation

/// A user-supplied Apple Game Porting Toolkit `redist/lib` directory. These
/// modules are Wine builtins and Unix bridges, not game-local native DLLs.
public struct D3DMetalRedist {
    public static let moduleNames = ["d3d11", "d3d12", "d3d12core", "dxgi"]
    public static let unixBridgeTarget = "../../external/libd3dshared.dylib"

    public let root: URL
    public var external: URL { root.appendingPathComponent("external") }
    public var framework: URL { external.appendingPathComponent("D3DMetal.framework") }
    public var sharedLibrary: URL { external.appendingPathComponent("libd3dshared.dylib") }
    public var windowsModules: URL { root.appendingPathComponent("wine/x86_64-windows") }
    public var unixModules: URL { root.appendingPathComponent("wine/x86_64-unix") }

    public init(root: URL) throws {
        self.root = try PathValidator.libraryDirectory(root.path)
        try validate()
    }

    public func validate() throws {
        let frameworkBinary = framework.appendingPathComponent("D3DMetal")
        guard frameworkBinary.resolvingSymlinksInPath().path.hasPrefix(framework.path + "/") else {
            throw OvercrossError.invalidPath("D3DMetal framework binary escapes its framework directory.")
        }
        try Self.requireX64MachO(sharedLibrary)
        try Self.requireX64MachO(frameworkBinary.resolvingSymlinksInPath())
        for name in Self.moduleNames {
            _ = try GameGraphicsSidecars.validatedPE(windowsModules.appendingPathComponent("\(name).dll"))
            let link = unixModules.appendingPathComponent("\(name).so")
            let values = try link.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink == true,
                  try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == Self.unixBridgeTarget,
                  link.resolvingSymlinksInPath() == sharedLibrary.resolvingSymlinksInPath() else {
                throw OvercrossError.invalidPath("D3DMetal Unix bridge must link to libd3dshared.dylib: \(link.path)")
            }
        }
    }

    private static func requireX64MachO(_ file: URL) throws {
        guard FileManager.default.isReadableFile(atPath: file.path),
              (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw OvercrossError.invalidPath("D3DMetal native bridge is missing: \(file.path)")
        }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        func big32(_ index: Int) -> UInt32 {
            UInt32(data[index]) << 24 | UInt32(data[index + 1]) << 16 |
            UInt32(data[index + 2]) << 8 | UInt32(data[index + 3])
        }
        let thinX64 = data.count >= 16 && Array(data.prefix(4)) == [0xcf, 0xfa, 0xed, 0xfe]
            && Array(data[4..<8]) == [7, 0, 0, 1]
        var fatX64 = false
        if data.count >= 8, Array(data.prefix(4)) == [0xca, 0xfe, 0xba, 0xbe] {
            let count = Int(big32(4))
            if count > 0, count <= 64, data.count >= 8 + count * 20 {
                fatX64 = (0..<count).contains { big32(8 + $0 * 20) == 0x0100_0007 }
            }
        }
        guard thinX64 || fatX64 else {
            throw OvercrossError.invalidPath("D3DMetal native bridge must contain x86_64 Mach-O code: \(file.path)")
        }
    }
}
