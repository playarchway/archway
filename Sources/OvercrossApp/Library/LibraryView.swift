import SwiftUI

/// The library: the Steam catalog as shelves and a grid over the focused game's artwork.
/// A game opens as a page on top, with its cover flying into place.
struct LibraryView: View {
    let store: LibraryStore

    @State private var openGame: LibraryGame?
    @State private var openHeroID: String?
    @State private var focusedGame: LibraryGame?
    @State private var search = ""
    @State private var showsSteamLogin = false
    @State private var isLinking = false
    @State private var linkError: String?
    @State private var showsImporter = false
    @Namespace private var hero

    private var filtered: [LibraryGame] {
        store.games.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
    }

    private var shelves: [(title: String, games: [LibraryGame], isLarge: Bool)] {
        let byRecency = filtered.filter { $0.lastPlayedAt != nil }.sorted { $0.lastPlayedAt! > $1.lastPlayedAt! }
        return [
            ("Weiterspielen", byRecency.filter { $0.isInstalled && !$0.isLocal }
                + filtered.filter { $0.isInstalled && !$0.isLocal && $0.lastPlayedAt == nil }, true),
            ("Zuletzt gespielt", Array(byRecency.filter { !$0.isInstalled }.prefix(12)), false),
            ("Eigene Spiele", filtered.filter(\.isLocal), false),
        ].filter { !$0.games.isEmpty }
    }

    var body: some View {
        ZStack {
            content
                .opacity(openGame == nil ? 1 : 0)
                .scaleEffect(openGame == nil ? 1 : 0.97)

            if let game = openGame, let openHeroID {
                GameDetailPage(game: game, heroNamespace: hero, heroID: openHeroID,
                               onRemove: game.isLocal ? { close(); store.removeLocalGame(game) } : nil)
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.animation(.easeOut(duration: 0.2))))
                    .zIndex(1)
            }
        }
        .background { AmbientBackground(game: openGame ?? focusedGame) }
        .navigationTitle(openGame?.title ?? "Bibliothek")
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .onChange(of: search) {
            if openGame != nil { close() }
        }
        .sheet(isPresented: $showsSteamLogin) {
            SteamLoginSheet {
                showsSteamLogin = false
                Task { await finishSteamLink() }
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.init(filenameExtension: "exe")!]) { result in
            if case .success(let url) = result { store.addLocalGame(executable: url) }
        }
        // Also picks up a Steam session that already exists, for example from an earlier sign-in.
        .task { await store.refresh() }
        // Let the backdrop run under the title bar so the window reads as one surface.
        .toolbarBackground(.hidden, for: .windowToolbar)
        .tint(.overcrossAccent)
        .preferredColorScheme(.dark)
    }

    private var subtitle: String {
        guard openGame == nil else { return "" }
        if store.phase == .loading { return "Wird aktualisiert …" }
        switch store.games.count {
        case 0: return ""
        case 1: return "1 Spiel"
        case let count: return "\(count) Spiele"
        }
    }

    private func finishSteamLink() async {
        isLinking = true
        defer { isLinking = false }
        await store.refresh()
        linkError = store.phase == .ready ? nil : "Steam hat die Verknüpfung nicht bestätigt. Versuche es erneut."
    }

    private func open(_ game: LibraryGame, heroID: String) {
        withAnimation(.overcrossHero) {
            openHeroID = heroID
            openGame = game
        }
    }

    private func close() {
        withAnimation(.overcrossHero) { openGame = nil }
    }

    // MARK: States

    @ViewBuilder private var content: some View {
        switch (store.phase, store.games.isEmpty) {
        case (.needsAccount, true):
            SourcePickerView(isLinking: isLinking, linkError: linkError,
                             onLinkSteam: { showsSteamLogin = true }, onAddGame: { showsImporter = true })
        case (.loading, true):
            ProgressView("Deine Steam-Bibliothek wird geladen …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case (.failed(let error), true):
            ContentUnavailableView {
                Label("Bibliothek nicht verfügbar", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.message)
            } actions: {
                Button("Erneut versuchen") { Task { await store.refresh() } }
                Button("Steam verknüpfen …") { showsSteamLogin = true }
            }
        case (.ready, true):
            ContentUnavailableView("Keine Spiele", systemImage: "gamecontroller",
                                   description: Text("In diesem Steam-Konto sind noch keine Spiele."))
        default:
            library
        }
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if case .failed(let error) = store.phase { staleBanner(error) }

                ForEach(shelves, id: \.title) { shelf in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(shelf.title).font(.title3.weight(.semibold)).padding(.horizontal, 32)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(shelf.games) { game in
                                    tile(game, width: shelf.isLarge ? 380 : 250, section: shelf.title)
                                }
                            }
                            .padding(.horizontal, 32)
                            .padding(.vertical, 10)
                        }
                    }
                }

                // The grid only adds something when the shelves do not already show every game.
                if !search.isEmpty || Set(shelves.flatMap { $0.games.map(\.id) }).count < filtered.count {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(search.isEmpty ? "Alle Spiele" : "Suchergebnisse")
                            .font(.title3.weight(.semibold))
                        if filtered.isEmpty {
                            Text("Kein Spiel passt zu „\(search)“.").foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 16, alignment: .top)], spacing: 22) {
                            ForEach(filtered) { game in
                                tile(game, width: nil, section: "all")
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                }
            }
            .padding(.vertical, 18)
        }
    }

    private func tile(_ game: LibraryGame, width: CGFloat?, section: String) -> some View {
        let heroID = "\(section)-\(game.id)"
        return ShelfTile(game: game, width: width, hero: hero, heroID: heroID,
                         isOpen: openGame != nil && openHeroID == heroID) {
            open(game, heroID: heroID)
        } onFocus: {
            focusedGame = game
        }
    }

    private func staleBanner(_ error: SteamCatalogError) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.message)
                if let lastUpdated = store.lastUpdated {
                    Text("Angezeigt wird der Stand vom \(lastUpdated.formatted(date: .abbreviated, time: .shortened)).")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            Spacer()
            if error == .notSignedIn {
                Button("Erneut verknüpfen") { showsSteamLogin = true }
            } else {
                Button("Erneut versuchen") { Task { await store.refresh() } }
            }
        }
        .padding(14)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 32)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if openGame != nil {
                Button(action: close) { Label("Bibliothek", systemImage: "chevron.left") }
                    .keyboardShortcut(.cancelAction)
                    .help("Zurück zur Bibliothek")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if !store.games.isEmpty { LibrarySearchField(text: $search) }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if openGame == nil && !store.games.isEmpty {
                Menu {
                    Button("Windows-Spiel hinzufügen …") { showsImporter = true }
                    if !store.hasAccount { Button("Steam verknüpfen …") { showsSteamLogin = true } }
                    Divider()
                    Button("GOG (bald verfügbar)") {}.disabled(true)
                    Button("Epic Games (bald verfügbar)") {}.disabled(true)
                    Button("itch.io (bald verfügbar)") {}.disabled(true)
                } label: {
                    Label("Spiele hinzufügen", systemImage: "plus")
                }
                .help("Spiele hinzufügen")
            }
            if store.hasAccount && openGame == nil {
                Button { Task { await store.refresh() } } label: {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                }
                .disabled(store.phase == .loading)
                .help("Bibliothek von Steam neu laden")
                Menu {
                    Button("Anderes Steam-Konto verknüpfen …") {
                        Task {
                            await store.signOut()
                            showsSteamLogin = true
                        }
                    }
                    Button("Steam-Verknüpfung aufheben", role: .destructive) { Task { await store.signOut() } }
                } label: {
                    Label("Steam-Konto", systemImage: "person.crop.circle")
                }
            }
        }
    }
}

private struct ShelfTile: View {
    let game: LibraryGame
    /// Fixed width on shelves; nil fills the grid column.
    let width: CGFloat?
    let hero: Namespace.ID
    let heroID: String
    let isOpen: Bool
    let onOpen: () -> Void
    let onFocus: () -> Void

    @State private var isHovered = false
    @State private var tilt: CGSize = .zero
    @State private var coverSize: CGSize = .zero

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                GameCover(game: game, cornerRadius: 10)
                    .saturation(game.isUnsupported ? 0 : 1)
                    .matchedGeometryEffect(id: heroID, in: hero, isSource: !isOpen)
                    .opacity(isOpen ? 0 : 1)
                    .rotation3DEffect(.degrees(Double(tilt.height) * -6), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                    .rotation3DEffect(.degrees(Double(tilt.width) * 8), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .scaleEffect(isHovered ? 1.04 : 1)
                    .shadow(color: .black.opacity(isHovered ? 0.5 : 0.25), radius: isHovered ? 18 : 6, y: isHovered ? 12 : 4)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { coverSize = $0 }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard coverSize.width > 0, coverSize.height > 0 else { return }
                            tilt = CGSize(width: location.x / coverSize.width - 0.5, height: location.y / coverSize.height - 0.5)
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
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.22)) { isHovered = hovering }
            if hovering { onFocus() }
        }
    }
}

/// The library search: brighter than the system field so it stays visible on the dark backdrop. ⌘F focuses it.
private struct LibrarySearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isFocused ? Color.overcrossAccent : .white.opacity(0.7))
            TextField("Bibliothek durchsuchen", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand { text = ""; isFocused = false }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.6))
                    .help("Suche leeren")
            }
        }
        .padding(.horizontal, 11)
        .frame(width: 260, height: 30)
        .background(.white.opacity(isFocused ? 0.16 : 0.11), in: Capsule())
        .overlay {
            Capsule().strokeBorder(isFocused ? Color.overcrossAccent.opacity(0.85) : .white.opacity(0.18), lineWidth: 1)
        }
        .animation(.snappy(duration: 0.18), value: isFocused)
        .background {
            Button("Suchen") { isFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }
}
