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
