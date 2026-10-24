import Darwin
import Foundation

/// Deploys an official, user-supplied GPTK redist into an already cloned Wine
/// runtime under Archway's runtime-overlays directory. It never edits the
/// source Wine installation or the Steam bottle.
public struct D3DMetalRuntimeOverlay {
    public enum Capability: String { case providerDeclared, unverified }

    public let paths: AppPaths
    public let runtimeRoot: URL
    public let redist: D3DMetalRedist
    public var wine: URL { runtimeRoot.appendingPathComponent("bin/wine") }
    public var wineserver: URL { runtimeRoot.appendingPathComponent("bin/wineserver") }
    public var backupDirectory: URL { runtimeRoot.appendingPathComponent(".\(LegacyStorage.name.lowercased())-d3dmetal-backup") }
    private var stateFile: URL { backupDirectory.appendingPathComponent("state.json") }

    private enum Kind: String, Codable { case file, framework, bridge }
    private struct Node {
        let relativePath: String
        let source: URL
        let kind: Kind
        func destination(in root: URL) -> URL { root.appendingPathComponent("lib/" + relativePath) }
    }
    private struct Entry: Codable {
        let relativePath: String
        let kind: Kind
        let originalFingerprint: String?
        let installedFingerprint: String
    }
    private struct State: Codable {
        let version: Int
        var phase: String
        let entries: [Entry]
    }

    public init(paths: AppPaths, runtimeRoot: URL, redist: D3DMetalRedist) throws {
        self.paths = paths
        self.runtimeRoot = try PathValidator.libraryDirectory(runtimeRoot.path)
        self.redist = redist
        let ownedRoot = paths.dataDirectory.appendingPathComponent("runtime-overlays").standardizedFileURL.path + "/"
        guard self.runtimeRoot.path.hasPrefix(ownedRoot) else {
            throw ArchwayError.invalidPath("D3DMetal runtime must be an Archway-owned clone under \(ownedRoot)")
        }
        try paths.validateBottleScope()
        _ = try PathValidator.executable(wine.path)
        _ = try PathValidator.executable(wineserver.path)
        for directory in ["lib/wine/x86_64-windows", "lib/wine/x86_64-unix"] {
            _ = try PathValidator.libraryDirectory(self.runtimeRoot.appendingPathComponent(directory).path)
        }
        try checkTargets()
    }

    /// Whisky's runtime archive keeps its metadata beside `Wine/`, not inside it.
    public var capability: Capability {
        let plist = runtimeRoot.deletingLastPathComponent().appendingPathComponent("WhiskyWineVersion.plist")
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = object as? [String: Any],
              values["gptkCapable"] as? Bool == true else { return .unverified }
        return .providerDeclared
    }

    /// A provider claim permits staging, but only a real mapped-module/game
    /// probe can establish that this runtime executes Apple's code correctly.
    public func stage(allowUnverifiedRuntime: Bool = false) throws {
        try stage(allowUnverifiedRuntime: allowUnverifiedRuntime, beforeReplace: { _ in })
    }

    func stage(allowUnverifiedRuntime: Bool,
               beforeReplace: (String) throws -> Void) throws {
        try redist.validate()
        guard capability == .providerDeclared || allowUnverifiedRuntime else {
            throw ArchwayError.invalidPath("This Wine clone has no recognized GPTK capability metadata. Supply a compatible runtime, or explicitly stage an unverified candidate for a controlled probe.")
        }
        guard try readState() == nil else {
            throw ArchwayError.invalidPath("D3DMetal is already staged in this runtime clone; restore before replacing it.")
        }
        let nodes = componentNodes()
        try checkTargets()
        try FileManager.default.createDirectory(at: runtimeRoot.appendingPathComponent("lib/external"),
                                                withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: backupDirectory.path) else {
            throw ArchwayError.invalidPath("D3DMetal runtime backup exists without valid state: \(backupDirectory.path)")
        }
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: false)
        var entries: [Entry] = []
        do {
            for node in nodes {
                let target = node.destination(in: runtimeRoot)
                let original = try fingerprint(target, kind: node.kind)
                if original != nil {
                    let backup = backupDirectory.appendingPathComponent(node.relativePath)
                    try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: target, to: backup)
                }
                let installed = try fingerprint(node.source, kind: node.kind)
                guard let installed else { throw ArchwayError.invalidPath("D3DMetal component is missing: \(node.source.path)") }
                entries.append(Entry(relativePath: node.relativePath, kind: node.kind,
                                     originalFingerprint: original, installedFingerprint: installed))
            }
            try saveState(State(version: 1, phase: "applying", entries: entries))
            for node in nodes {
                try beforeReplace(node.relativePath)
                try replace(node.source, at: node.destination(in: runtimeRoot), kind: node.kind)
            }
            try saveState(State(version: 1, phase: "staged", entries: entries))
        } catch {
            if FileManager.default.fileExists(atPath: stateFile.path) {
                try restore()
            } else {
                try? FileManager.default.removeItem(at: backupDirectory)
            }
            throw error
        }
    }

    public func isStaged() throws -> Bool {
        guard let state = try readState(), state.phase == "staged" else { return false }
        for entry in state.entries {
            if try fingerprint(runtimeRoot.appendingPathComponent("lib/" + entry.relativePath), kind: entry.kind)
                != entry.installedFingerprint { return false }
        }
        return true
    }

    public func restore() throws {
        guard let state = try readState() else { return }
        for entry in state.entries {
            let target = runtimeRoot.appendingPathComponent("lib/" + entry.relativePath)
            let current = try fingerprint(target, kind: entry.kind)
            guard current == entry.installedFingerprint || current == entry.originalFingerprint else {
                throw ArchwayError.invalidPath("D3DMetal runtime component changed; refusing to overwrite \(target.path).")
            }
            if let original = entry.originalFingerprint {
                let backup = backupDirectory.appendingPathComponent(entry.relativePath)
                guard try fingerprint(backup, kind: entry.kind) == original else {
                    throw ArchwayError.invalidPath("D3DMetal runtime backup is missing or changed: \(backup.path)")
                }
                if current != original { try replace(backup, at: target, kind: entry.kind) }
            } else if current != nil {
                try FileManager.default.removeItem(at: target)
            }
        }
        try FileManager.default.removeItem(at: backupDirectory)
    }

    private func componentNodes() -> [Node] {
        var nodes = [
            Node(relativePath: "external/D3DMetal.framework", source: redist.framework, kind: .framework),
            Node(relativePath: "external/libd3dshared.dylib", source: redist.sharedLibrary, kind: .file)
        ]
        for name in D3DMetalRedist.moduleNames {
            nodes.append(Node(relativePath: "wine/x86_64-windows/\(name).dll",
                              source: redist.windowsModules.appendingPathComponent("\(name).dll"), kind: .file))
            nodes.append(Node(relativePath: "wine/x86_64-unix/\(name).so",
                              source: redist.unixModules.appendingPathComponent("\(name).so"), kind: .bridge))
        }
        return nodes
    }

    private func readState() throws -> State? {
        try checkTargets()
        guard FileManager.default.fileExists(atPath: stateFile.path) else { return nil }
        guard (try? stateFile.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw ArchwayError.invalidPath("D3DMetal state must not be a symlink.")
        }
        let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: stateFile))
        let expected = Dictionary(uniqueKeysWithValues: componentNodes().map { ($0.relativePath, $0.kind) })
        guard state.version == 1, ["applying", "staged"].contains(state.phase),
              state.entries.count == expected.count,
              state.entries.allSatisfy({ expected[$0.relativePath] == $0.kind }),
              Set(state.entries.map(\.relativePath)).count == expected.count else {
            throw ArchwayError.invalidPath("D3DMetal runtime state is invalid.")
        }
        return state
    }

    private func saveState(_ state: State) throws {
        try JSONEncoder().encode(state).write(to: stateFile, options: [.atomic])
    }

    private func checkTargets() throws {
        for node in componentNodes() {
            let target = node.destination(in: runtimeRoot)
            var parent = target.deletingLastPathComponent()
            while parent.path.hasPrefix(runtimeRoot.path), parent.path != runtimeRoot.path {
                if (try? parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    throw ArchwayError.invalidPath("D3DMetal runtime directory must not be a symlink: \(parent.path)")
                }
                parent.deleteLastPathComponent()
            }
        }
        if (try? backupDirectory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw ArchwayError.invalidPath("D3DMetal backup must not be a symlink.")
        }
    }

    private func fingerprint(_ url: URL, kind: Kind) throws -> String? {
        let fm = FileManager.default
        if kind == .bridge {
            if let destination = try? fm.destinationOfSymbolicLink(atPath: url.path) {
                return "link:" + destination
            }
            return fm.fileExists(atPath: url.path) ? try GameGraphicsSidecars.hash(url) : nil
        }
        guard fm.fileExists(atPath: url.path) else { return nil }
        if kind == .framework {
            let binary = url.appendingPathComponent("D3DMetal")
            guard fm.fileExists(atPath: binary.path) else { return "invalid" }
            return try GameGraphicsSidecars.hash(binary.resolvingSymlinksInPath())
        }
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return "invalid" }
        return try GameGraphicsSidecars.hash(url)
    }

    private func replace(_ source: URL, at target: URL, kind: Kind) throws {
        let fm = FileManager.default
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".archway-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temporary) }
        if kind == .bridge, let link = try? fm.destinationOfSymbolicLink(atPath: source.path) {
            try fm.createSymbolicLink(atPath: temporary.path, withDestinationPath: link)
        } else {
            try fm.copyItem(at: source, to: temporary)
        }
        if kind == .framework, fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        guard rename(temporary.path, target.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
