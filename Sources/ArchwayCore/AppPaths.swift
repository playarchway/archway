import Foundation

public struct AppPaths: Sendable {
    public let dataDirectory: URL
    public var config: URL { dataDirectory.appendingPathComponent("config.json") }
    public var bottle: URL { dataDirectory.appendingPathComponent("bottles/steam-5228920") }
    public var logs: URL { dataDirectory.appendingPathComponent("logs") }

    /// Without a directory, the default under Application Support. Run `DataMigration` first for that one.
    public init(dataDirectory: URL? = nil) throws {
        let selected = dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Archway")
        guard selected.isFileURL, selected.path.hasPrefix("/"), selected.path != "/" else {
            throw ArchwayError.invalidPath("Data directory must be an absolute local directory other than /.")
        }
        self.dataDirectory = selected.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func ensureDirectories() throws {
        try validateBottleScope()
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try validateBottleScope()
    }

    public func validateBottleScope() throws {
        for location in [dataDirectory, bottle.deletingLastPathComponent(), bottle, logs] {
            guard !isSymlink(location) else {
                throw ArchwayError.invalidPath("Archway directory must not be a symlink: \(location.path)")
            }
        }
    }

    private func isSymlink(_ location: URL) -> Bool {
        (try? location.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}

public struct BottleMarker: Codable, Equatable {
    public let version: Int
    public let state: State

    public enum State: String, Codable { case initializing, ready }
    public init(state: State) { version = 1; self.state = state }
}
