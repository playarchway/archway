import AppKit
import ArchwayCore

/// A game's Mac version. Steam for macOS installs and starts it; Archway shows it and hands it over.
@MainActor
enum MacVersion {
    static let steamDownload = URL(string: "https://store.steampowered.com/about/")!

    /// Steam for macOS, if it is installed.
    static var steamApp: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.valvesoftware.steam") }

    /// Opens a steam:// link in Steam for macOS, never in the Windows Steam in Archway's bottle.
    static func open(_ link: String) {
        guard let app = steamApp, let url = URL(string: link) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Whether the player picked the Mac version of a game that has one. Without a choice, it is the Mac version,
    /// unless the Windows version is already installed.
    static func isChosen(for game: LibraryGame) -> Bool {
        (UserDefaults.standard.dictionary(forKey: choicesKey)?[String(game.id)] as? Bool) ?? !game.isInstalled
    }

    static func choose(_ mac: Bool, for game: LibraryGame) {
        var choices = UserDefaults.standard.dictionary(forKey: choicesKey) ?? [:]
        choices[String(game.id)] = mac
        UserDefaults.standard.set(choices, forKey: choicesKey)
    }

    private static let choicesKey = "macVersionChoices"
}
