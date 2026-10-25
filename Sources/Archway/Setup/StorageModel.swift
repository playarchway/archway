import AppKit
import Observation
import WebKit
import ArchwayCore

/// How much space Archway takes, and removing Archway with everything it set up.
@MainActor
@Observable
final class StorageModel {
    private(set) var totalBytes: Int?
    private(set) var gameBytes: Int?
    private(set) var isRemoving = false

    private let paths: AppPaths

    init(paths: AppPaths) { self.paths = paths }

    func measure() async {
        let paths = paths
        let (total, games) = await Task.detached {
            let games = (try? ConfigStore(paths: paths).load()).flatMap {
                Orchestrator(paths: paths, configuration: $0).steamGamesDirectory
            }
            return (DiskUsage.allocatedSize(of: paths.dataDirectory), games.map(DiskUsage.allocatedSize) ?? 0)
        }.value
        totalBytes = total
        gameBytes = games
    }

    func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([paths.dataDirectory])
    }

    /// Ends Archway's Wine sessions, deletes its data, caches, settings, and Steam web sign-in,
    /// moves the app to the Trash, and quits. With ARCHWAY_DATA_DIR, only that directory goes.
    func removeArchway() async {
        isRemoving = true
        let dataDirectory = paths.dataDirectory
        let isolated = ProcessInfo.processInfo.environment["ARCHWAY_DATA_DIR"] != nil
        await Task.detached { ArchwayRemoval.stopWine(dataDirectory: dataDirectory) }.value
        if isolated {
            await Task.detached { ArchwayRemoval.delete([dataDirectory]) }.value
        } else {
            let store = WKWebsiteDataStore.default()
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
            let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            let files = ArchwayRemoval.filesToDelete(dataDirectory: dataDirectory, library: library,
                                                     bundleIdentifier: Bundle.main.bundleIdentifier)
            await Task.detached { ArchwayRemoval.delete(files) }.value
            if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
            if Bundle.main.bundleURL.pathExtension == "app" {
                _ = try? await NSWorkspace.shared.recycle([Bundle.main.bundleURL])
            }
        }
        NSApp.terminate(nil)
    }
}
