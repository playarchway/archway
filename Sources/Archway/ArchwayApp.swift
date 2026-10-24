import AppKit
import SwiftUI

@main
struct ArchwayApp: App {
    @State private var store: LibraryStore
    @State private var runner: GameRunner

    init() {
        let store = LibraryStore()
        _store = State(initialValue: store)
        _runner = State(initialValue: GameRunner(store: store))
        // Started through SwiftPM without an app bundle; make it a regular foreground app.
        NSApplication.shared.setActivationPolicy(.regular)
        AppIcon.current.apply()
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup("Archway") {
            LibraryView(store: store)
                .environment(runner)
        }
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandGroup(before: .appTermination) {
                Button("Quit Steam") { runner.quitSteam() }
                    .disabled(!runner.canQuitSteam)
                Divider()
            }
        }

        Settings {
            AppSettingsView()
                .preferredColorScheme(.dark)
        }
    }
}
