import Foundation
import Observation
import ArchwayCore

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
        /// A new runtime is ready, but Steam still runs on the old one; the user quits it.
        case needsSteamQuit
        case failed(Step, String)
        case ready
    }

    private(set) var phase: Phase = .checking
    /// How far the current download is, from 0 to 1.
    private(set) var progress: Double?
    /// The runtime package that replaces an earlier release's, while Archway switches to it.
    private(set) var runtimeUpdate: RuntimeRelease?
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

    /// Asks Steam to exit, waits for its Wine server, then finishes the runtime update.
    func quitSteam() {
        guard phase == .needsSteamQuit else { return }
        phase = .working(.runtime)
        let paths = paths
        Task {
            try? await Task.detached {
                let orchestrator = try Orchestrator(paths: paths)
                try ProcessRunner.sendGUIRequest(orchestrator.steamShutdown())
                try ProcessRunner.runSetup(orchestrator.wineserverWait(), timeout: 30)
            }.value
            start()
        }
    }

    /// How much of the whole setup is done, from 0 to 1, counting the current download.
    var fractionDone: Double {
        let steps = Double(Step.allCases.count)
        switch phase {
        case .ready: return 1
        case .checking, .needsRosetta: return 0
        case .needsSteamQuit: return (Double(Step.runtime.rawValue) + 1) / steps
        case .working(let step), .failed(let step, _): return (Double(step.rawValue) + (progress ?? 0)) / steps
        }
    }

    /// Whether a step is behind the current one, for the checklist.
    func isDone(_ step: Step) -> Bool {
        switch phase {
        case .ready: true
        case .working(let current), .failed(let current, _): step < current
        case .needsSteamQuit: step < .runtime
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
            guard try await installRuntimeIfNeeded() else {
                phase = .needsSteamQuit
                return
            }
            step = .bottle
            phase = .working(step)
            let paths = paths
            try await Task.detached { try Orchestrator(paths: paths).initializeBottle() }.value
            step = .steam
            phase = .working(step)
            try await installSteamIfNeeded()
            runtimeUpdate = nil
            phase = .ready
        } catch {
            phase = .failed(step, error.localizedDescription)
        }
        progress = nil
    }

    /// Keeps a runtime set up by hand, for example from the command line. A runtime package of an earlier
    /// release gives way to this release's, and is removed once the bottle runs on the new one. Returns false
    /// while Steam still runs on the old package.
    private func installRuntimeIfNeeded() async throws -> Bool {
        let paths = paths
        let store = ConfigStore(paths: paths)
        let release = try RuntimeRelease.bundled()
        let previous = try store.load().flatMap { FileManager.default.isExecutableFile(atPath: $0.wine) ? $0 : nil }
        if let previous {
            guard RuntimeRelease.isPackaged(previous, in: paths) else { return true }
            guard previous.wine != release.configuration(in: paths).wine else {
                try? release.removeOtherPackages(in: paths)
                return true
            }
            runtimeUpdate = release
        }
        if !release.isInstalled(in: paths) {
            // ARCHWAY_RUNTIME_ARCHIVE uses a local package instead, while the runtime isn't published.
            let override = ProcessInfo.processInfo.environment["ARCHWAY_RUNTIME_ARCHIVE"].map(URL.init(fileURLWithPath:))
            let archive = if let override { override } else { try await download(release.url) }
            defer { if override == nil { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) } }
            progress = nil
            try await Task.detached { try release.install(archive: archive, in: paths) }.value
        }
        guard let previous else {
            try store.save(release.configuration(in: paths))
            return true
        }
        let old = Orchestrator(paths: paths, configuration: previous)
        if old.wineserverIsRunning() { return false }
        try store.save(release.configuration(in: paths))
        if old.bottleIsInitialized() {
            do {
                try await Task.detached { try Orchestrator(paths: paths).updateBottle() }.value
            } catch {
                // Back to the old package, which stays until an update works.
                try? store.save(previous)
                throw error
            }
        }
        try? release.removeOtherPackages(in: paths)
        return true
    }

    private func installSteamIfNeeded() async throws {
        let paths = paths
        guard try Orchestrator(paths: paths).steamExecutable() == nil else { return }
        let installer = try await download(SteamSetup.installerURL, as: "SteamSetup.exe")
        defer { try? FileManager.default.removeItem(at: installer.deletingLastPathComponent()) }
        progress = nil
        try await Task.detached { try SteamSetup.install(installer, with: Orchestrator(paths: paths)) }.value
    }

    private func download(_ url: URL, as name: String? = nil) async throws -> URL {
        progress = 0
        return try await Download.run(url, name: name ?? url.lastPathComponent) { fraction in
            Task { @MainActor in self.progress = fraction }
        }
    }
}
