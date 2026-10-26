import AppKit
import SwiftUI
import ArchwayCore

@main
struct ArchwayApp: App {
    @State private var store: LibraryStore?
    @State private var runner: GameRunner?
    @State private var compatibility: CompatibilityStore?
    @State private var setup: SetupModel?
    @State private var storage: StorageModel?
    private let startupError: String?

    init() {
        do {
            let paths = try AppPaths.app()
            let store = LibraryStore(paths: paths)
            let compatibility = CompatibilityStore(paths: paths)
            _store = State(initialValue: store)
            _compatibility = State(initialValue: compatibility)
            _runner = State(initialValue: GameRunner(paths: paths, store: store, compatibility: compatibility))
            _setup = State(initialValue: SetupModel(paths: paths))
            _storage = State(initialValue: StorageModel(paths: paths))
            startupError = nil
        } catch {
            _store = State(initialValue: nil)
            _runner = State(initialValue: nil)
            _compatibility = State(initialValue: nil)
            _setup = State(initialValue: nil)
            _storage = State(initialValue: nil)
            startupError = String(localized: "Archway couldn't prepare its data. Check the data folders in Application Support and close any Wine session using the old folder. For details, run archway migrate-data in Terminal.")
        }
        // Started through SwiftPM without an app bundle; make it a regular foreground app.
        NSApplication.shared.setActivationPolicy(.regular)
        AppIcon.current.apply()
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup("Archway") {
            if let store, let runner, let setup, let compatibility {
                LibraryView(store: store)
                    .environment(runner)
                    .environment(compatibility)
                    .environment(setup)
                    .task { setup.start() }
                    .task { await compatibility.refreshCatalog() }
            } else {
                ContentUnavailableView {
                    Label("Unable to open Archway data", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(verbatim: startupError ?? "")
                        .textSelection(.enabled)
                }
            }
        }
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandGroup(before: .appTermination) {
                Button("Open Steam") { runner?.openSteam() }
                    .disabled(setup?.isReady != true)
                Button("Quit Steam") { runner?.quitSteam() }
                    .disabled(runner?.canQuitSteam != true)
                Divider()
            }
        }

        Settings {
            AppSettingsView(runner: runner, setup: setup, storage: storage, compatibility: compatibility)
                .preferredColorScheme(.dark)
        }
    }
}
