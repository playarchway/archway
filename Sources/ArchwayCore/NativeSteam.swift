import Foundation

/// Steam for macOS, which installs and starts the Mac versions of games. Archway only reads its library and hands
/// games to it through steam:// links; it never runs or changes this Steam itself.
public struct NativeSteam: Sendable {
    public enum GameState: Equatable, Sendable {
        case notInstalled
        /// Steam has a manifest for the game but hasn't finished downloading it.
        case installing
        /// False when the game's app is built only for architectures this Mac can't run, such as old 32-bit ports.
        case installed(runsOnThisMac: Bool)
    }

    /// Steam's data folder, which holds the default library and the list of the others.
    public let root: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Steam")) {
        self.root = root
    }

    public func state(of appID: Int) -> GameState {
        for library in libraries() {
            let steamapps = library.appendingPathComponent("steamapps")
            let manifestURL = steamapps.appendingPathComponent("appmanifest_\(appID).acf")
            guard let manifest = try? String(contentsOf: manifestURL, encoding: .utf8) else { continue }
            // StateFlags bit 4 is "fully installed"; updates add other bits but keep it.
            let flags = Self.values(of: "StateFlags", in: manifest).first.flatMap(Int.init) ?? 0
            guard flags & 4 != 0 else { return .installing }
            let folder = Self.values(of: "installdir", in: manifest).first
                .map { steamapps.appendingPathComponent("common").appendingPathComponent($0) }
            return .installed(runsOnThisMac: folder.map(Self.runsOnThisMac) ?? true)
        }
        return .notInstalled
    }

    /// The default library plus the others in libraryfolders.vdf, for example on an external drive.
    func libraries() -> [URL] {
        let list = try? String(contentsOf: root.appendingPathComponent("steamapps/libraryfolders.vdf"), encoding: .utf8)
        let others = list.map { Self.values(of: "path", in: $0) } ?? []
        var seen = Set<String>()
        return ([root] + others.map { URL(fileURLWithPath: $0) }).filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// Whether any app in the game's folder runs on Apple silicon, natively or through Rosetta. A folder without an
    /// app (some ports ship a bare binary) counts as runnable: Archway can't tell.
    static func runsOnThisMac(_ folder: URL) -> Bool {
        let apps = appBundles(in: folder, depth: 2)
        guard !apps.isEmpty else { return true }
        let usable: Set<Int> = [NSBundleExecutableArchitectureARM64, NSBundleExecutableArchitectureX86_64]
        return apps.contains { app in
            Bundle(url: app)?.executableArchitectures?.contains { usable.contains($0.intValue) } ?? false
        }
    }

    private static func appBundles(in folder: URL, depth: Int) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                                     options: .skipsHiddenFiles)) ?? []
        return entries.flatMap { entry -> [URL] in
            if entry.pathExtension == "app" { return [entry] }
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDirectory && depth > 1 ? appBundles(in: entry, depth: depth - 1) : []
        }
    }

    /// The values of `"key"  "value"` lines in Steam's KeyValues files (.acf, .vdf), in order.
    static func values(of key: String, in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            return parts.count >= 4 && parts[1].caseInsensitiveCompare(key) == .orderedSame ? String(parts[3]) : nil
        }
    }
}
