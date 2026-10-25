import Foundation

/// Removing Archway with everything it set up. macOS gives apps no hook when they are moved to the Trash,
/// so the app offers this instead.
public enum ArchwayRemoval {
    /// Ends the Wine sessions of every bottle Archway configured, in the data directory or one level below it.
    public static func stopWine(dataDirectory: URL) {
        let nested = (try? FileManager.default.contentsOfDirectory(at: dataDirectory, includingPropertiesForKeys: nil)) ?? []
        for directory in [dataDirectory] + nested {
            guard let paths = try? AppPaths(dataDirectory: directory),
                  let configuration = try? ConfigStore(paths: paths).load(),
                  let wineserver = configuration.wineserver,
                  Orchestrator(paths: paths, configuration: configuration).wineserverIsRunning() else { continue }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: wineserver)
            process.arguments = ["-k"]
            process.environment = ["WINEPREFIX": paths.bottle.path]
            try? process.run()
            process.waitUntilExit()
        }
    }

    /// The data directory and, with a bundle identifier, the app's caches, web data, and saved window state
    /// in `library`. Settings in UserDefaults are the caller's to clear.
    public static func filesToDelete(dataDirectory: URL, library: URL, bundleIdentifier: String?) -> [URL] {
        guard let id = bundleIdentifier else { return [dataDirectory] }
        return [dataDirectory] + ["Caches/\(id)", "WebKit/\(id)", "HTTPStorages/\(id)", "HTTPStorages/\(id).binarycookies",
                                  "Saved Application State/\(id).savedState"].map { library.appendingPathComponent($0) }
    }

    public static func delete(_ files: [URL]) {
        for file in files { try? FileManager.default.removeItem(at: file) }
    }
}
