import Foundation
import Observation
import ArchwayCore

extension AppPaths {
    /// Archway's data directory. ARCHWAY_DATA_DIR points the app at another one, for example to try a first start.
    /// Moves legacy data first, so call it once at launch and pass the result on.
    static func app() throws -> AppPaths {
        if let custom = ProcessInfo.processInfo.environment["ARCHWAY_DATA_DIR"] {
            return try AppPaths(dataDirectory: URL(fileURLWithPath: custom))
        }
        try DataMigration.migrateIfNeeded()
        return try AppPaths()
    }
}

/// Sets up everything Archway needs on first start, in the background: Rosetta, the Wine runtime,
/// the Windows bottle, and Windows Steam. Each step checks first, so a later start only verifies.
@MainActor
@Observable
final class SetupModel {
    enum Step: Int, CaseIterable, Comparable {
        case rosetta, runtime, bottle, steam

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .rosetta: String(localized: "Rosetta")
            case .runtime: String(localized: "Windows Runtime")
            case .bottle: String(localized: "Windows Environment")
            case .steam: String(localized: "Windows Steam")
            }
        }
    }

    enum Phase: Equatable {
        case checking
        case working(Step)
        /// Rosetta needs an administrator password, so the user starts its installation.
        case needsRosetta
        case failed(Step, String)
        case ready
    }

    private(set) var phase: Phase = .checking
    /// How far the current download is, from 0 to 1.
    private(set) var progress: Double?
    var isReady: Bool { phase == .ready }

    private let paths: AppPaths
    private var task: Task<Void, Never>?

    init(paths: AppPaths) { self.paths = paths }

    func start() {
        guard task == nil, !isReady else { return }
        task = Task {
            await run()
            task = nil
        }
    }

    func installRosetta() {
        guard phase == .needsRosetta else { return }
        phase = .working(.rosetta)
        Task {
            do {
                try await Task.detached { try Rosetta.install() }.value
                start()
            } catch {
                // Cancelling the password dialog lands here too; the user can try again.
                phase = .needsRosetta
            }
        }
    }

    /// How much of the whole setup is done, from 0 to 1, counting the current download.
    var fractionDone: Double {
        let steps = Double(Step.allCases.count)
        switch phase {
        case .ready: return 1
        case .checking, .needsRosetta: return 0
        case .working(let step), .failed(let step, _): return (Double(step.rawValue) + (progress ?? 0)) / steps
        }
    }

    /// Whether a step is behind the current one, for the checklist.
    func isDone(_ step: Step) -> Bool {
        switch phase {
        case .ready: true
        case .working(let current), .failed(let current, _): step < current
        case .needsRosetta, .checking: false
        }
    }

    private func run() async {
        var step = Step.rosetta
        do {
            phase = .working(step)
            guard await Task.detached(operation: { Rosetta.isInstalled() }).value else {
                phase = .needsRosetta
                return
            }
            step = .runtime
            phase = .working(step)
            try await installRuntimeIfNeeded()
            step = .bottle
            phase = .working(step)
            let paths = paths
            try await Task.detached { try Self.orchestrator(paths).initializeBottle() }.value
            step = .steam
            phase = .working(step)
            try await installSteamIfNeeded()
            phase = .ready
        } catch {
            phase = .failed(step, error.localizedDescription)
        }
        progress = nil
    }

    /// Keeps a runtime that is already configured, for example from the command line.
    private func installRuntimeIfNeeded() async throws {
        let paths = paths
        if let configuration = try ConfigStore(paths: paths).load(),
           FileManager.default.isExecutableFile(atPath: configuration.wine) { return }
        let release = try RuntimeRelease.bundled()
        if !release.isInstalled(in: paths) {
            // ARCHWAY_RUNTIME_ARCHIVE uses a local package instead, while the runtime isn't published.
            let override = ProcessInfo.processInfo.environment["ARCHWAY_RUNTIME_ARCHIVE"].map(URL.init(fileURLWithPath:))
            let archive = if let override { override } else { try await download(release.url) }
            defer { if override == nil { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) } }
            progress = nil
            try await Task.detached { try release.install(archive: archive, in: paths) }.value
        }
        try ConfigStore(paths: paths).save(release.configuration(in: paths))
    }

    private func installSteamIfNeeded() async throws {
        let paths = paths
        guard try Self.orchestrator(paths).steamExecutable() == nil else { return }
        let installer = try await download(SteamSetup.installerURL, as: "SteamSetup.exe")
        defer { try? FileManager.default.removeItem(at: installer.deletingLastPathComponent()) }
        progress = nil
        try await Task.detached { try SteamSetup.install(installer, with: Self.orchestrator(paths)) }.value
    }

    private func download(_ url: URL, as name: String? = nil) async throws -> URL {
        progress = 0
        return try await Download.run(url, name: name ?? url.lastPathComponent) { fraction in
            Task { @MainActor in self.progress = fraction }
        }
    }

    nonisolated private static func orchestrator(_ paths: AppPaths) throws -> Orchestrator {
        guard let configuration = try ConfigStore(paths: paths).load() else { throw ArchwayError.missingConfiguration }
        return Orchestrator(paths: paths, configuration: configuration)
    }
}

/// A file download that reports its progress. The file lands in its own temporary folder under `name`.
private final class Download: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let name: String
    private let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    private init(name: String, onProgress: @escaping @Sendable (Double) -> Void) {
        self.name = name
        self.onProgress = onProgress
    }

    static func run(_ url: URL, name: String, onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let download = Download(name: name, onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: download, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            download.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The system deletes `location` after this returns, so move it now.
        do {
            if let response = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                throw URLError(.badServerResponse)
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(name)
            try FileManager.default.moveItem(at: location, to: file)
            continuation?.resume(returning: file)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
