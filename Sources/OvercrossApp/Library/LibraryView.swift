import SwiftUI

/// The library: shelves of games over the focused game's artwork; a game opens as a page on top,
/// with its cover flying into place.
struct LibraryView: View {
    // OVERCROSS_PREVIEW_GAME=<app id> opens that game's page on launch, for design screenshots.
    @State private var openGame: PreviewGame? = ProcessInfo.processInfo.environment["OVERCROSS_PREVIEW_GAME"]
        .flatMap(Int.init).flatMap { id in PreviewLibrary.games.first { $0.id == id } }
    @State private var focusedGame = PreviewLibrary.games[0]
    @State private var search = ""
    @Namespace private var hero

    private var shelves: [(title: String, games: [PreviewGame], isLarge: Bool)] {
        let games = PreviewLibrary.games.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
        return [
            ("Zuletzt gespielt", games.filter { $0.lastPlayed != nil }, true),
            ("Ausprobieren", games.filter { !$0.isInstalled && !$0.isUnsupported }, false),
            ("Läuft nicht auf dem Mac", games.filter(\.isUnsupported), false),
        ].filter { !$0.games.isEmpty }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    ForEach(shelves, id: \.title) { shelf in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(shelf.title).font(.title3.weight(.semibold)).padding(.horizontal, 32)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 16) {
                                    ForEach(shelf.games) { game in
                                        ShelfTile(game: game, width: shelf.isLarge ? 380 : 250,
                                                  hero: hero, isOpen: openGame?.id == game.id) {
                                            withAnimation(.overcrossHero) { openGame = game }
                                        } onFocus: {
                                            focusedGame = game
                                        }
                                    }
                                }
                                .padding(.horizontal, 32)
                                .padding(.vertical, 10)
                            }
                        }
                    }
                }
                .padding(.vertical, 18)
            }
            .opacity(openGame == nil ? 1 : 0)
            .scaleEffect(openGame == nil ? 1 : 0.97)

            if let game = openGame {
                GameDetailPage(game: game, heroNamespace: hero)
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.animation(.easeOut(duration: 0.2))))
                    .zIndex(1)
            }
        }
        .background { AmbientBackground(game: openGame ?? focusedGame) }
        .navigationTitle(openGame?.title ?? "Bibliothek")
        .navigationSubtitle(openGame == nil ? "\(PreviewLibrary.totalCount) Spiele aus Steam" : "")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if openGame != nil {
                    Button {
                        withAnimation(.overcrossHero) { openGame = nil }
                    } label: {
                        Label("Bibliothek", systemImage: "chevron.left")
                    }
                    .keyboardShortcut(.cancelAction)
                    .help("Zurück zur Bibliothek")
                }
            }
        }
        .searchable(text: $search, prompt: "Bibliothek durchsuchen")
        .onChange(of: search) {
            if openGame != nil { withAnimation(.overcrossHero) { openGame = nil } }
        }
        .tint(.overcrossAccent)
        .preferredColorScheme(.dark)
    }
}

private struct ShelfTile: View {
    let game: PreviewGame
    let width: CGFloat
    let hero: Namespace.ID
    let isOpen: Bool
    let onOpen: () -> Void
    let onFocus: () -> Void

    @State private var isHovered = false
    @State private var tilt: CGSize = .zero

    private var coverHeight: CGFloat { width * 215 / 460 }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                GameCover(game: game, cornerRadius: 10)
                    .saturation(game.isUnsupported ? 0 : 1)
                    .matchedGeometryEffect(id: game.id, in: hero, isSource: !isOpen)
                    .opacity(isOpen ? 0 : 1)
                    .rotation3DEffect(.degrees(Double(tilt.height) * -6), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                    .rotation3DEffect(.degrees(Double(tilt.width) * 8), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .scaleEffect(isHovered ? 1.04 : 1)
                    .shadow(color: .black.opacity(isHovered ? 0.5 : 0.25), radius: isHovered ? 18 : 6, y: isHovered ? 12 : 4)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            tilt = CGSize(width: location.x / width - 0.5, height: location.y / coverHeight - 0.5)
                        case .ended:
                            tilt = .zero
                        }
                    }
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: tilt)
                Text(game.title).font(.callout.weight(.medium)).lineLimit(1)
                HStack(spacing: 10) {
                    CompatibilityBadge(compatibility: game.compatibility)
                    if game.isInstalled { Label("Installiert", systemImage: "internaldrive").font(.caption) }
                }
                .foregroundStyle(.secondary)
            }
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.22)) { isHovered = hovering }
            if hovering { onFocus() }
        }
    }
}
