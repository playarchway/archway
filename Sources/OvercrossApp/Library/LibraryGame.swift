import SwiftUI

/// One game in the library: what Steam reports, plus what Overcross knows about running it.
struct LibraryGame: Identifiable, Hashable {
    enum Compatibility: Hashable {
        case tested
        case experimental
        case untested
        case unsupported(String)

        var label: String {
            switch self {
            case .tested: "Getestet"
            case .experimental: "Experimentell"
            case .untested: "Ungetestet"
            case .unsupported: "Nicht unterstützt"
            }
        }

        var symbol: String {
            switch self {
            case .tested: "checkmark.seal.fill"
            case .experimental: "flask.fill"
            case .untested: "circle.dashed"
            case .unsupported: "nosign"
            }
        }

        var color: Color {
            switch self {
            case .tested: .green
            case .experimental: .orange
            case .untested: .secondary
            case .unsupported: .red
            }
        }

        var headline: String {
            switch self {
            case .tested: "Läuft auf deinem Mac"
            case .experimental: "Startet, noch nicht ganz getestet"
            case .untested: "Noch nicht ausprobiert"
            case .unsupported: "Läuft nicht auf dem Mac"
            }
        }

        var explanation: String {
            switch self {
            case .tested: "Spielen, Speichern und Laden funktionieren auf diesem Mac."
            case .experimental: "Das Spiel startet. Ob alles funktioniert, ist noch nicht geprüft."
            case .untested: "Du kannst es ausprobieren. Overcross wählt passende Einstellungen."
            case .unsupported(let reason): "Der Anti-Cheat-Schutz \(reason) funktioniert mit Overcross nicht."
            }
        }
    }

    let id: Int
    let title: String
    let playtimeMinutes: Int
    let lastPlayedAt: Date?
    var isInstalled: Bool
    var compatibility: Compatibility
    var backend: String
    /// Set for games added from a local .exe; nil for Steam games.
    var executablePath: String? = nil

    var isLocal: Bool { executablePath != nil }

    var headerURL: URL {
        URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(id)/header.jpg")!
    }

    /// A stable color per game for placeholders and backdrops before artwork loads.
    var tint: Color {
        Color(hue: Double(id % 360) / 360, saturation: 0.45, brightness: 0.55)
    }

    var playtime: String? {
        guard playtimeMinutes > 0 else { return nil }
        if playtimeMinutes < 60 { return "\(playtimeMinutes) Min." }
        let hours = Double(playtimeMinutes) / 60
        return hours < 10 ? String(format: "%.1f Std.", hours).replacingOccurrences(of: ".", with: ",", range: nil)
                          : "\(Int(hours.rounded())) Std."
    }

    var lastPlayed: String? {
        guard let lastPlayedAt else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(lastPlayedAt) { return "Heute" }
        if calendar.isDateInYesterday(lastPlayedAt) { return "Gestern" }
        return lastPlayedAt.formatted(.dateTime.day().month(.abbreviated).year())
    }

    var isPlayable: Bool { isInstalled && !isUnsupported }
    var isUnsupported: Bool { if case .unsupported = compatibility { true } else { false } }
}

/// Steam header image. Newer games keep it under a hashed path, so a failed load asks the store for the real URL.
struct GameCover: View {
    let game: LibraryGame
    var cornerRadius: CGFloat = 8
    var contentMode: ContentMode = .fit
    @State private var storeURL: URL?

    var body: some View {
        if game.isLocal {
            placeholder
                .aspectRatio(460.0 / 215.0, contentMode: contentMode)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            steamCover
        }
    }

    private var steamCover: some View {
        AsyncImage(url: storeURL ?? game.headerURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder.task {
                    guard storeURL == nil else { return }
                    storeURL = try? await SteamStoreClient.shared.details(for: game.id).headerImage
                }
            default:
                placeholder
            }
        }
        .aspectRatio(460.0 / 215.0, contentMode: contentMode)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        LinearGradient(colors: [game.tint, game.tint.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Text(game.title).font(.headline).foregroundStyle(.white.opacity(0.85)).padding(8))
    }
}

struct CompatibilityBadge: View {
    let compatibility: LibraryGame.Compatibility
    var showsLabel = true

    var body: some View {
        Label {
            if showsLabel { Text(compatibility.label) }
        } icon: {
            Image(systemName: compatibility.symbol).foregroundStyle(compatibility.color)
        }
        .font(.caption.weight(.medium))
    }
}
