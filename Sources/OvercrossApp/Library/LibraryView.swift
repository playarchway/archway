import SwiftUI

/// The library: shelves of games; each game opens its own detail page.
struct LibraryView: View {
    // OVERCROSS_PREVIEW_GAME=<app id> opens that game's page on launch, for design screenshots.
    @State private var path: [PreviewGame.ID] = ProcessInfo.processInfo.environment["OVERCROSS_PREVIEW_GAME"]
        .flatMap(Int.init).map { [$0] } ?? []
    @State private var search = ""

    private var shelves: [(title: String, games: [PreviewGame], isLarge: Bool)] {
        let games = PreviewLibrary.games.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
        return [
            ("Zuletzt gespielt", games.filter { $0.lastPlayed != nil }, true),
            ("Ausprobieren", games.filter { !$0.isInstalled && !$0.isUnsupported }, false),
            ("Läuft nicht auf dem Mac", games.filter(\.isUnsupported), false),
        ].filter { !$0.games.isEmpty }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    ForEach(shelves, id: \.title) { shelf in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(shelf.title).font(.title3.weight(.semibold)).padding(.horizontal, 32)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 16) {
                                    ForEach(shelf.games) { game in
                                        NavigationLink(value: game.id) {
                                            ShelfTile(game: game, width: shelf.isLarge ? 380 : 250)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 32)
                            }
                        }
                    }
                }
                .padding(.vertical, 28)
            }
            .background {
                LinearGradient(colors: [Color(red: 0.16, green: 0.2, blue: 0.27), .black],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
            .navigationTitle("Bibliothek")
            .navigationSubtitle("\(PreviewLibrary.totalCount) Spiele aus Steam")
            .searchable(text: $search, prompt: "Bibliothek durchsuchen")
            .navigationDestination(for: PreviewGame.ID.self) { id in
                if let game = PreviewLibrary.games.first(where: { $0.id == id }) {
                    GameDetailPage(game: game)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ShelfTile: View {
    let game: PreviewGame
    let width: CGFloat
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GameCover(game: game, cornerRadius: 10)
                .saturation(game.isUnsupported ? 0 : 1)
                .overlay(alignment: .bottomLeading) {
                    if game.isPlayable && isHovered {
                        Label("Details", systemImage: "chevron.right.circle.fill")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }
                }
                .scaleEffect(isHovered ? 1.03 : 1)
                .shadow(color: .black.opacity(isHovered ? 0.45 : 0.2), radius: isHovered ? 16 : 6, y: 6)
            Text(game.title).font(.callout.weight(.medium)).lineLimit(1)
            HStack(spacing: 10) {
                CompatibilityBadge(compatibility: game.compatibility)
                if game.isInstalled { Label("Installiert", systemImage: "internaldrive").font(.caption) }
            }
            .foregroundStyle(.secondary)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.snappy(duration: 0.18)) { isHovered = hovering } }
    }
}
