import Foundation

/// Installing Steam games without Steam's install dialog. Archway writes an app manifest that asks for an
/// update; Steam picks it up when it starts and downloads the game in the background, also with `-silent`.
/// A running Steam only reads new manifests on its next start.
extension Orchestrator {
    /// Steam's state bit for a fully installed app.
    static let fullyInstalledFlag = 4
    /// Update required (2) plus update started (1024), which makes Steam download the app on start.
    static let queuedInstallFlags = 1026

    /// Writes the manifest that queues the game, unless Steam already knows it. Returns whether it wrote one.
    @discardableResult
    public func queueSteamInstall(appID: Int, name: String) throws -> Bool {
        guard let steamapps = steamAppsDirectory else { throw ArchwayError.missingSteam }
        let manifest = steamapps.appendingPathComponent("appmanifest_\(appID).acf")
        guard !FileManager.default.fileExists(atPath: manifest.path) else { return false }
        let fields = [("appid", String(appID)), ("Universe", "1"), ("name", name),
                      ("StateFlags", String(Self.queuedInstallFlags)), ("installdir", Self.installFolderName(name, appID: appID)),
                      ("LastUpdated", "0"), ("SizeOnDisk", "0"), ("buildid", "0"), ("AutoUpdateBehavior", "0")]
        let body = fields.map { "\t\"\($0.0)\"\t\t\"\(Self.escaped($0.1))\"" }.joined(separator: "\n")
        try FileManager.default.createDirectory(at: steamapps, withIntermediateDirectories: true)
        try Data("\"AppState\"\n{\n\(body)\n}\n".utf8).write(to: manifest, options: [.atomic])
        return true
    }

    /// How far Steam is with a queued or running download, from 0 to 1; nil before Steam has sized it.
    /// Steam writes `BytesDownloaded` only when it finishes, so this measures the download folder instead.
    /// Steam preallocates part of it, so the value jumps a little at the start.
    public func steamInstallProgress(appID: Int) -> Double? {
        guard let steamapps = steamAppsDirectory,
              let text = try? String(contentsOf: steamapps.appendingPathComponent("appmanifest_\(appID).acf"), encoding: .utf8),
              let total = GameProcesses.value(of: "BytesToStage", inManifest: text).flatMap(Double.init), total > 0 else {
            return nil
        }
        let folder = steamapps.appendingPathComponent("downloading/\(appID)")
        return min(1, Double(Self.allocatedSize(of: folder)) / total)
    }

    static func allocatedSize(of folder: URL) -> Int {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys)) else { return 0 }
        return files.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: keys) } }
            .filter { $0.isRegularFile == true }
            .reduce(0) { $0 + ($1.totalFileAllocatedSize ?? 0) }
    }

    public enum SteamInstallPhase: Equatable, Sendable {
        /// Steam is starting, waiting in its queue, or preallocating the game's files.
        case preparing
        case downloading
        /// Steam moves the downloaded files into place and checks them.
        case installing
    }

    /// The phase Steam's content log names last for the game, or nil before Steam has picked it up.
    public func steamInstallPhase(appID: Int) -> SteamInstallPhase? {
        guard let steam = steamExecutable(),
              let log = Self.tail(of: steam.deletingLastPathComponent().appendingPathComponent("logs/content_log.txt")) else {
            return nil
        }
        return Self.installPhase(appID: appID, contentLog: log)
    }

    static func installPhase(appID: Int, contentLog: String) -> SteamInstallPhase? {
        let marker = "AppID \(appID) App update changed : "
        guard let line = contentLog.split(separator: "\n").last(where: { $0.contains(marker) }),
              let range = line.range(of: marker) else { return nil }
        let flags = line[range.upperBound...]
        if flags.contains("Committing") || flags.contains("Verifying") || flags.contains("Validating") { return .installing }
        if flags.contains("Downloading") { return .downloading }
        return .preparing
    }

    /// The end of a log that can grow to megabytes.
    private static func tail(of file: URL, bytes: Int = 64 * 1024) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > UInt64(bytes) ? size - UInt64(bytes) : 0)
        return (try? handle.readToEnd()).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Removes an installed game the way Steam does, without its confirmation dialog: the manifest, the game
    /// folder, and its shader cache and unfinished download. Saves outside the game folder stay. Steam must not run.
    public func uninstallSteamGame(appID: Int) throws {
        guard let steamapps = steamAppsDirectory else { throw ArchwayError.missingSteam }
        let manifest = steamapps.appendingPathComponent("appmanifest_\(appID).acf")
        let fm = FileManager.default
        if let text = try? String(contentsOf: manifest, encoding: .utf8),
           let folder = GameProcesses.value(of: "installdir", inManifest: text) {
            guard !folder.isEmpty, !folder.contains("/"), !folder.contains("\\"), folder != "..", folder != "." else {
                throw ArchwayError.invalidPath("Steam's manifest names an unexpected game folder: \(folder)")
            }
            try? fm.removeItem(at: steamapps.appendingPathComponent("common").appendingPathComponent(folder))
        }
        for leftover in ["downloading/\(appID)", "shadercache/\(appID)"] {
            try? fm.removeItem(at: steamapps.appendingPathComponent(leftover))
        }
        if fm.fileExists(atPath: manifest.path) { try fm.removeItem(at: manifest) }
    }

    /// Whether Windows Steam has a remembered sign-in, so it can start without showing its login window.
    public func steamIsSignedIn() -> Bool {
        guard let steam = steamExecutable(),
              let text = try? String(contentsOf: steam.deletingLastPathComponent().appendingPathComponent("config/loginusers.vdf"),
                                     encoding: .utf8) else { return false }
        return text.range(of: #""RememberPassword"\s+"1""#, options: .regularExpression) != nil
    }

    /// A folder name Windows accepts. Steam installs into the manifest's `installdir`.
    static func installFolderName(_ name: String, appID: Int) -> String {
        let invalid = CharacterSet(charactersIn: "<>:\"/\\|?*").union(.controlCharacters)
        let cleaned = name.replacingOccurrences(of: "™", with: "").replacingOccurrences(of: "®", with: "")
            .unicodeScalars.filter { !invalid.contains($0) }.map(String.init).joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return cleaned.isEmpty ? "App \(appID)" : cleaned
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
