import CryptoKit
import Darwin
import Foundation

/// Reconciles only Brick by Brick's app-local Direct3D DLLs. D3DMetal uses Wine
/// builtin forwarders in a compatible runtime, so its game directory must not
/// contain native DXVK sidecars. Steam and CEF are outside this directory.
public struct GameGraphicsSidecars {
    public static let gameRelativePath = "drive_c/Program Files (x86)/Steam/steamapps/common/Brick by Brick Tidy Up the Small Town!/BrickByBrick.exe"
    public static let allowedNames: Set<String> = ["d3d11.dll", "d3d12.dll", "d3d12core.dll", "dxgi.dll"]

    public let paths: AppPaths
    public var gameExecutable: URL { paths.bottle.appendingPathComponent(Self.gameRelativePath) }
    public var gameDirectory: URL { gameExecutable.deletingLastPathComponent() }
    public var backupDirectory: URL { paths.dataDirectory.appendingPathComponent("graphics-backups/brick-by-brick") }
    private var stateFile: URL { backupDirectory.appendingPathComponent("state.json") }

    public init(paths: AppPaths) throws {
        self.paths = paths
        try paths.validateBottleScope()
        let marker = paths.bottle.appendingPathComponent(".archway-bottle.json")
        let registry = paths.bottle.appendingPathComponent("system.reg")
        guard try Self.isRegular(marker), try Self.isRegular(registry),
              let ownership = try? JSONDecoder().decode(BottleMarker.self, from: Data(contentsOf: marker)),
              ownership.version == 1, ownership.state == .ready else {
            throw ArchwayError.missingBottle
        }
        try Self.checkDirectoryChain(gameDirectory, within: paths.bottle)
        guard try Self.isRegular(gameExecutable) else {
            throw ArchwayError.invalidPath("BrickByBrick.exe is missing from the owned Steam bottle.")
        }
        try Self.checkDirectoryChain(backupDirectory, within: paths.dataDirectory)
    }

    public func installedBackend() throws -> GraphicsBackend? { try readState()?.backend }

    /// A normal D3DMetal launch must not silently use app-local DXVK or an
    /// existing Wine native override. The profile is prepared only while the
    /// owned bottle is stopped; this check itself is read-only.
    public func requireD3DMetalReady() throws {
        for name in Self.allowedNames {
            if FileManager.default.fileExists(atPath: gameDirectory.appendingPathComponent(name).path) {
                throw ArchwayError.invalidPath("D3DMetal game profile has an app-local \(name); suspend the DXVK sidecars first.")
            }
        }
        let registry = paths.bottle.appendingPathComponent("user.reg")
        guard try Self.isRegular(registry) else {
            throw ArchwayError.invalidPath("Wine user registry is missing; cannot verify game-only builtin D3D overrides.")
        }
        let contents = try String(contentsOf: registry, encoding: .utf8)
        let section = "[Software\\\\Wine\\\\AppDefaults\\\\BrickByBrick.exe\\\\DllOverrides]"
        guard let start = contents.range(of: section) else {
            throw ArchwayError.invalidPath("Brick by Brick has no D3DMetal builtin overrides in user.reg.")
        }
        let remainder = contents[start.upperBound...]
        let body = remainder.prefix(while: { $0 != "[" })
        for name in ["d3d11", "d3d12", "d3d12core", "dxgi"] {
            guard body.contains("\"\(name)\"=\"builtin\"") else {
                throw ArchwayError.invalidPath("Brick by Brick requires a game-only builtin override for \(name); D3DMetal launch refused.")
            }
        }
    }

    /// DXVK sources are explicit Windows x64 PE files. Stop the owned bottle first.
    public func apply(_ sources: [String: URL], backend: GraphicsBackend) throws {
        try apply(sources, backend: backend, beforeInstall: { _ in })
    }

    func apply(_ sources: [String: URL], backend: GraphicsBackend,
               beforeInstall: (String) throws -> Void) throws {
        guard backend == .dxvk, Set(sources.keys) == ["d3d11.dll", "dxgi.dll"] else {
            throw ArchwayError.invalidPath("Only DXVK d3d11.dll and dxgi.dll may be installed beside the game.")
        }
        try change(sources, names: sources.keys.sorted(), backend: backend, beforeInstall: beforeInstall)
    }

    /// Removes app-local Direct3D files while preserving exact originals for
    /// rollback. Apple D3DMetal files belong in a compatible Wine runtime.
    public func suspendForD3DMetal() throws {
        try change([:], names: Self.allowedNames.sorted(), backend: .d3dmetal, beforeInstall: { _ in })
    }

    private func change(_ sources: [String: URL], names: [String], backend: GraphicsBackend,
                        beforeInstall: (String) throws -> Void) throws {
        guard try readState() == nil else {
            throw ArchwayError.invalidPath("A game graphics profile is already applied; restore it before switching.")
        }
        for name in names {
            if let source = sources[name] { _ = try Self.validatedPE(source) }
            try Self.checkTarget(gameDirectory.appendingPathComponent(name))
        }
        let parent = backupDirectory.deletingLastPathComponent()
        try Self.checkDirectoryChain(parent, within: paths.dataDirectory)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: backupDirectory.path) else {
            throw ArchwayError.invalidPath("Graphics backup directory already exists without a valid state; inspect it before retrying: \(backupDirectory.path)")
        }
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: false)
        var savedState = State(version: 1, backend: backend, files: [])
        do {
            for name in names {
                let target = gameDirectory.appendingPathComponent(name)
                let originalHash = try Self.isRegular(target) ? Self.hash(target) : nil
                if originalHash != nil {
                    try Self.atomicCopy(target, to: backupDirectory.appendingPathComponent(name))
                }
                savedState.files.append(Entry(name: name, originalHash: originalHash,
                                              installedHash: try sources[name].map(Self.hash)))
            }
            try JSONEncoder().encode(savedState).write(to: stateFile, options: [.atomic])
            for name in names {
                try beforeInstall(name)
                let target = gameDirectory.appendingPathComponent(name)
                if let source = sources[name] {
                    try Self.atomicCopy(source, to: target)
                } else if try Self.isRegular(target) {
                    try FileManager.default.removeItem(at: target)
                }
            }
        } catch {
            if FileManager.default.fileExists(atPath: stateFile.path) {
                try restore()
            } else {
                try? FileManager.default.removeItem(at: backupDirectory)
            }
            throw error
        }
    }

    public func restore() throws {
        guard let state = try readState() else { return }
        for entry in state.files {
            let target = gameDirectory.appendingPathComponent(entry.name)
            try Self.checkTarget(target)
            let currentHash = try Self.isRegular(target) ? Self.hash(target) : nil
            guard currentHash == entry.installedHash || currentHash == entry.originalHash else {
                throw ArchwayError.invalidPath("Game DLL changed since graphics installation; refusing to overwrite \(target.path).")
            }
            if let originalHash = entry.originalHash {
                let backup = backupDirectory.appendingPathComponent(entry.name)
                guard try Self.isRegular(backup), try Self.hash(backup) == originalHash else {
                    throw ArchwayError.invalidPath("Original game DLL backup is missing or changed: \(backup.path)")
                }
                if currentHash != originalHash { try Self.atomicCopy(backup, to: target) }
            } else if currentHash != nil {
                try FileManager.default.removeItem(at: target)
            }
        }
        try FileManager.default.removeItem(at: backupDirectory)
    }

    private struct Entry: Codable {
        let name: String
        let originalHash: String?
        let installedHash: String?
    }

    private struct State: Codable {
        let version: Int
        let backend: GraphicsBackend
        var files: [Entry]
    }

    private func readState() throws -> State? {
        try Self.checkDirectoryChain(backupDirectory, within: paths.dataDirectory)
        guard FileManager.default.fileExists(atPath: stateFile.path) else { return nil }
        guard try Self.isRegular(stateFile) else {
            throw ArchwayError.invalidPath("Graphics state must be a regular file: \(stateFile.path)")
        }
        let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: stateFile))
        guard state.version == 1, state.backend != .builtin, !state.files.isEmpty,
              Set(state.files.map(\.name)).isSubset(of: Self.allowedNames),
              Set(state.files.map(\.name)).count == state.files.count else {
            throw ArchwayError.invalidPath("Graphics backup state is invalid: \(stateFile.path)")
        }
        return state
    }

    private static func checkDirectoryChain(_ directory: URL, within root: URL) throws {
        let rootPath = root.standardizedFileURL.path
        let path = directory.standardizedFileURL.path
        guard path == rootPath || path.hasPrefix(rootPath + "/") else {
            throw ArchwayError.invalidPath("Graphics path escapes its owned directory: \(path)")
        }
        var current = root
        for part in path.dropFirst(rootPath.count).split(separator: "/") {
            current.appendPathComponent(String(part))
            if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw ArchwayError.invalidPath("Graphics directory must not be a symlink: \(current.path)")
            }
        }
    }

    private static func checkTarget(_ target: URL) throws {
        if (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw ArchwayError.invalidPath("Game DLL target must not be a symlink: \(target.path)")
        }
        if FileManager.default.fileExists(atPath: target.path), try !isRegular(target) {
            throw ArchwayError.invalidPath("Game DLL target must be a regular file: \(target.path)")
        }
    }

    private static func isRegular(_ file: URL) throws -> Bool {
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        guard values.isSymbolicLink != true else {
            throw ArchwayError.invalidPath("Graphics file must not be a symlink: \(file.path)")
        }
        return values.isRegularFile == true
    }

    static func validatedPE(_ file: URL) throws -> URL {
        guard try isRegular(file), FileManager.default.isReadableFile(atPath: file.path) else {
            throw ArchwayError.invalidPath("Direct3D component must be a readable regular file: \(file.path)")
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let dos = try handle.read(upToCount: 64) ?? Data()
        guard dos.count == 64, dos[0] == 0x4d, dos[1] == 0x5a else {
            throw ArchwayError.invalidPath("Direct3D component is not a Windows PE file: \(file.path)")
        }
        let offset = UInt64(dos[0x3c]) | UInt64(dos[0x3d]) << 8 | UInt64(dos[0x3e]) << 16 | UInt64(dos[0x3f]) << 24
        guard offset >= 64, offset < 1_048_576 else {
            throw ArchwayError.invalidPath("Direct3D component has an invalid PE header: \(file.path)")
        }
        try handle.seek(toOffset: offset)
        let header = try handle.read(upToCount: 6) ?? Data()
        guard header.count == 6, Array(header.prefix(4)) == [0x50, 0x45, 0, 0],
              header[4] == 0x64, header[5] == 0x86 else {
            throw ArchwayError.invalidPath("Direct3D component must be a Windows x64 DLL: \(file.path)")
        }
        return file
    }

    static func hash(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { digest.update(data: chunk) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func atomicCopy(_ source: URL, to target: URL) throws {
        try checkTarget(target)
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".archway-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(at: source, to: temporary)
        guard rename(temporary.path, target.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
