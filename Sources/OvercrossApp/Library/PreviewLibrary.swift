import SwiftUI

/// Sample library for comparing the design variants. Replaced by the Steam catalog later.
struct PreviewGame: Identifiable, Hashable {
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
    let compatibility: Compatibility
    let isInstalled: Bool
    let hasMacVersion: Bool
    let graphicsAPI: String
    let backend: String
    let playtime: String?
    let lastPlayed: String?
    let tint: Color
    var headerURL: URL

    init(id: Int, title: String, compatibility: Compatibility, isInstalled: Bool = false, hasMacVersion: Bool = false,
         graphicsAPI: String, backend: String, playtime: String? = nil, lastPlayed: String? = nil,
         tint: Color, headerURL: String? = nil) {
        self.id = id
        self.title = title
        self.compatibility = compatibility
        self.isInstalled = isInstalled
        self.hasMacVersion = hasMacVersion
        self.graphicsAPI = graphicsAPI
        self.backend = backend
        self.playtime = playtime
        self.lastPlayed = lastPlayed
        self.tint = tint
        self.headerURL = URL(string: headerURL
            ?? "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(id)/header.jpg")!
    }

    var isPlayable: Bool { isInstalled && compatibility != .untested && !isUnsupported }
    var isUnsupported: Bool { if case .unsupported = compatibility { true } else { false } }
}

enum PreviewLibrary {
    static let games: [PreviewGame] = [
        PreviewGame(id: 5_228_920, title: "Brick by Brick: Tidy Up the Small Town!", compatibility: .tested,
                    isInstalled: true, graphicsAPI: "Direct3D 11", backend: "D3DMetal",
                    playtime: "22 Min.", lastPlayed: "Heute",
                    tint: Color(red: 0.42, green: 0.64, blue: 0.84),
                    headerURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/5228920/8c57f18ab6a1940b328584fe5556f4c87839e1a0/header.jpg"),
        PreviewGame(id: 1_594_320, title: "Captain of Industry", compatibility: .experimental, isInstalled: true,
                    graphicsAPI: "Direct3D 11", backend: "D3DMetal", playtime: "3 Std.", lastPlayed: "Juli",
                    tint: Color(red: 0.55, green: 0.47, blue: 0.33)),
        PreviewGame(id: 1_942_280, title: "Brotato", compatibility: .untested, hasMacVersion: true,
                    graphicsAPI: "Direct3D 11", backend: "D3DMetal", tint: Color(red: 0.62, green: 0.45, blue: 0.62)),
        PreviewGame(id: 526_870, title: "Satisfactory", compatibility: .untested,
                    graphicsAPI: "Direct3D 12", backend: "D3DMetal", tint: Color(red: 0.85, green: 0.55, blue: 0.2)),
        PreviewGame(id: 1_066_780, title: "Transport Fever 2", compatibility: .untested, hasMacVersion: true,
                    graphicsAPI: "OpenGL", backend: "WineD3D", tint: Color(red: 0.36, green: 0.55, blue: 0.4)),
        PreviewGame(id: 1_144_200, title: "Ready or Not", compatibility: .unsupported("Easy Anti-Cheat"),
                    graphicsAPI: "Direct3D 12", backend: "–", tint: Color(red: 0.3, green: 0.34, blue: 0.38)),
        PreviewGame(id: 242_920, title: "Banished", compatibility: .untested,
                    graphicsAPI: "Direct3D 11", backend: "D3DMetal", tint: Color(red: 0.45, green: 0.52, blue: 0.4)),
        PreviewGame(id: 221_100, title: "DayZ", compatibility: .unsupported("BattlEye"),
                    graphicsAPI: "Direct3D 11", backend: "–", tint: Color(red: 0.4, green: 0.42, blue: 0.38)),
        PreviewGame(id: 945_360, title: "Among Us", compatibility: .untested,
                    graphicsAPI: "Direct3D 11", backend: "D3DMetal", tint: Color(red: 0.75, green: 0.25, blue: 0.25)),
        PreviewGame(id: 218_620, title: "PAYDAY 2", compatibility: .untested,
                    graphicsAPI: "Direct3D 9", backend: "WineD3D", tint: Color(red: 0.25, green: 0.4, blue: 0.6)),
        PreviewGame(id: 550, title: "Left 4 Dead 2", compatibility: .untested,
                    graphicsAPI: "Direct3D 9", backend: "WineD3D", tint: Color(red: 0.6, green: 0.2, blue: 0.15)),
        PreviewGame(id: 251_570, title: "7 Days to Die", compatibility: .untested,
                    graphicsAPI: "Direct3D 11", backend: "D3DMetal", tint: Color(red: 0.5, green: 0.36, blue: 0.25)),
    ]

    static let totalCount = 109
}

/// Steam header image with a tinted placeholder while it loads or when it is missing.
struct GameCover: View {
    let game: PreviewGame
    var cornerRadius: CGFloat = 8

    var body: some View {
        AsyncImage(url: game.headerURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                LinearGradient(colors: [game.tint, game.tint.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Text(game.title).font(.headline).foregroundStyle(.white.opacity(0.85)).padding(8))
            }
        }
        .aspectRatio(460.0 / 215.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct CompatibilityBadge: View {
    let compatibility: PreviewGame.Compatibility
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
