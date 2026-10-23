import AppKit
import SwiftUI

@main
struct OvercrossApp: App {
    init() {
        // Started through SwiftPM without an app bundle; make it a regular foreground app.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup("Overcross") {
            LibraryView()
        }
        .defaultSize(width: 1320, height: 840)
    }
}
