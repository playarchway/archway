import CryptoKit
import Darwin
import Foundation

/// Moves a game's own Direct3D DLLs aside for D3DMetal. Some games ship DXVK or other Direct3D DLLs beside
/// their executables, which Wine would load instead of the runtime's builtin forwarders. Exact originals stay
/// in a backup for rollback. Steam and CEF are outside the game folder.
public struct GameGraphicsSidecars {
    public static let allowedNames: Set<String> = ["d3d11.dll", "d3d12.dll", "d3d12core.dll", "dxgi.dll"]
    /// Libraries the game must take from the runtime, set as game-only Wine overrides.
    public static let builtinLibraries = ["d3d10", "d3d11", "d3d12", "d3d12core", "dxgi"]

    public let paths: AppPaths
    public let gameDirectory: URL
    public let backupDirectory: URL
    /// The game's executables, which get the builtin overrides.
    public let executables: [URL]
    private var stateFile: URL { backupDirectory.appendingPathComponent("state.json") }

    /// `backupName` keeps one game's backup apart from the others, for example its Steam app ID.
    public init(paths: AppPaths, gameDirectory: URL, backupName: String) throws {
        self.paths = paths
        self.gameDirectory = gameDirectory
        backupDirectory = paths.dataDirectory.appendingPathComponent("graphics-backups").appendingPathComponent(backupName)
        try paths.validateBottleScope()
        let marker = paths.bottle.appendingPathComponent(".archway-bottle.json")
        let registry = paths.bottle.appendingPathComponent("system.reg")
        guard try Self.isRegular(marker), try Self.isRegular(registry),
              let ownership = try? JSONDecoder().decode(BottleMarker.self, from: Data(contentsOf: marker)),
              ownership.version == 1, ownership.state == .ready else {
            throw ArchwayError.missingBottle
        }
        try Self.checkDirectoryChain(gameDirectory, within: paths.bottle)
        guard (try? gameDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw ArchwayError.invalidPath("The game folder is missing from the owned Steam bottle: \(gameDirectory.path)")
        }
        guard !backupName.isEmpty, !backupName.contains("/"), !backupName.hasPrefix(".") else {
            throw ArchwayError.invalidPath("Invalid graphics backup name '\(backupName)'.")
        }
        executables = GameProcesses.executables(in: gameDirectory)
        try Self.checkDirectoryChain(backupDirectory, within: paths.dataDirectory)
    }

    public func installedBackend() throws -> GraphicsBackend? { try readState()?.backend }

    /// Direct3D DLLs that sit beside one of the game's executables, relative to the game folder.
    var sidecarNames: [String] {
        let folders = Set(executables.map { $0.deletingLastPathComponent().standardizedFileURL.path })
        let root = gameDirectory.standardizedFileURL.path
        return folders.sorted().flatMap { folder in
            let prefix = folder == root ? "" : String(folder.dropFirst(root.count + 1)) + "/"
            return Self.allowedNames.sorted().map { prefix + $0 }
        }
    }

    /// A D3DMetal launch must not silently use the game's own Direct3D DLLs. Moved DLLs also need the game-only
    /// builtin overrides. Read-only; `Orchestrator.prepareD3DMetalGame` sets the game up.
    public func requireD3DMetalReady() throws {
        for name in sidecarNames where FileManager.default.fileExists(atPath: gameDirectory.appendingPathComponent(name).path) {
            throw ArchwayError.invalidPath("The game has its own \(name); move it aside before a D3DMetal launch.")
        }
        guard try readState() != nil else { return }
        let registry = paths.bottle.appendingPathComponent("user.reg")
        guard try Self.isRegular(registry) else {
            throw ArchwayError.invalidPath("Wine user registry is missing; cannot verify game-only builtin D3D overrides.")
        }
        let contents = try String(contentsOf: registry, encoding: .utf8).lowercased()
        for executable in executables {
            let section = "[software\\\\wine\\\\appdefaults\\\\\(executable.lastPathComponent.lowercased())\\\\dlloverrides]"
            guard let start = contents.range(of: section) else {
                throw ArchwayError.invalidPath("\(executable.lastPathComponent) has no D3DMetal builtin overrides in user.reg.")
            }
            let body = contents[start.upperBound...].prefix(while: { $0 != "[" })
            for name in Self.builtinLibraries where !body.contains("\"\(name)\"=\"builtin\"") {
                throw ArchwayError.invalidPath("\(executable.lastPathComponent) needs a game-only builtin override for \(name); D3DMetal launch refused.")
            }
        }
    }

    /// Removes the game's own Direct3D files while keeping exact originals for rollback.
    /// Apple D3DMetal files belong in a compatible Wine runtime. Stop the owned bottle first.
    public func suspendForD3DMetal() throws {
        guard try readState() == nil else {
            throw ArchwayError.invalidPath("A game graphics profile is already applied; restore it before switching.")
        }
        let names = sidecarNames
        for name in names { try Self.checkTarget(gameDirectory.appendingPathComponent(name)) }
        let parent = backupDirectory.deletingLastPathComponent()
        try Self.checkDirectoryChain(parent, within: paths.dataDirectory)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: backupDirectory.path) else {
            throw ArchwayError.invalidPath("Graphics backup directory already exists without a valid state; inspect it before retrying: \(backupDirectory.path)")
        }
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: false)
        var savedState = State(version: 1, backend: .d3dmetal, files: [])
        do {
            for name in names {
                let target = gameDirectory.appendingPathComponent(name)
                let originalHash = try Self.isRegular(target) ? Self.hash(target) : nil
                if originalHash != nil {
                    let backup = backupDirectory.appendingPathComponent(name)
                    try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Self.atomicCopy(target, to: backup)
                }
                savedState.files.append(Entry(name: name, originalHash: originalHash, installedHash: nil))
            }
            try JSONEncoder().encode(savedState).write(to: stateFile, options: [.atomic])
            for name in names {
                let target = gameDirectory.appendingPathComponent(name)
                if try Self.isRegular(target) { try FileManager.default.removeItem(at: target) }
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
              state.files.allSatisfy({ Self.isSidecarName($0.name) }),
              Set(state.files.map(\.name)).count == state.files.count else {
            throw ArchwayError.invalidPath("Graphics backup state is invalid: \(stateFile.path)")
        }
        return state
    }

    /// `d3d11.dll` or `Folder/d3d11.dll`: one of the allowed names, at most one folder deep, never leaving the game.
    private static func isSidecarName(_ name: String) -> Bool {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count <= 2 && allowedNames.contains(String(parts.last ?? ""))
            && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
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
