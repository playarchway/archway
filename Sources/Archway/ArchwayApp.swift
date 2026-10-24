import AppKit
import SwiftUI
import ArchwayCore

@main
struct ArchwayApp: App {
    @State private var store: LibraryStore?
    @State private var runner: GameRunner?
    private let startupError: String?

    init() {
        do {
            let paths = try AppPaths()
            let store = LibraryStore(paths: paths)
            _store = State(initialValue: store)
            _runner = State(initialValue: GameRunner(store: store))
            startupError = nil
        } catch {
            _store = State(initialValue: nil)
            _runner = State(initialValue: nil)
            startupError = String(localized: "Archway couldn't prepare its data. Check the data folders in Application Support and close any Wine session using the old folder. For details, run archway migrate-data in Terminal.")
        }
        // Started through SwiftPM without an app bundle; make it a regular foreground app.
        NSApplication.shared.setActivationPolicy(.regular)
        AppIcon.current.apply()
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup("Archway") {
            if let store, let runner {
                LibraryView(store: store)
                    .environment(runner)
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
                Button("Quit Steam") { runner?.quitSteam() }
                    .disabled(runner?.canQuitSteam != true)
                Divider()
            }
        }

        Settings {
            AppSettingsView()
                .preferredColorScheme(.dark)
        }
    }
}
