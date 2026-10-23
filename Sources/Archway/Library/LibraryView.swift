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
            (String(localized: "Continue Playing"), byRecency.filter { $0.isInstalled && !$0.isLocal }
                + filtered.filter { $0.isInstalled && !$0.isLocal && $0.lastPlayedAt == nil }, true),
            (String(localized: "Recently Played"), Array(byRecency.filter { !$0.isInstalled }.prefix(12)), false),
            (String(localized: "Your Own Games"), filtered.filter(\.isLocal), false),
        ].filter { !$0.games.isEmpty }
    }

    var body: some View {
        ZStack {
            content
                .opacity(openGame == nil ? 1 : 0)
                .scaleEffect(openGame == nil ? 1 : 0.97)

            if let opened = openGame, let openHeroID {
                // Look the game up again so its stats follow the store, for example after a session ends.
                let game = store.games.first { $0.id == opened.id } ?? opened
                GameDetailPage(game: game, heroNamespace: hero, heroID: openHeroID,
                               onRemove: game.isLocal ? { close(); store.removeLocalGame(game) } : nil)
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.animation(.easeOut(duration: 0.2))))
                    .zIndex(1)
            }
        }
        .background { AmbientBackground(game: openGame ?? focusedGame) }
        // The game page and the empty start page carry their own large headings.
        .navigationTitle(openGame == nil && !store.games.isEmpty ? String(localized: "Library") : "")
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        // Steam's playtime may have moved since the library loaded, for example after playing on another device.
        .onChange(of: openGame?.id) {
            if let openGame, !openGame.isLocal { Task { await store.refresh() } }
        }
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
        // OVERCROSS_PREVIEW_GAME=<app id> opens that game's page once the library has loaded, for design screenshots.
        .onChange(of: store.games.count, initial: true) {
            guard openGame == nil, let id = ProcessInfo.processInfo.environment["OVERCROSS_PREVIEW_GAME"].flatMap(Int.init),
                  let game = store.games.first(where: { $0.id == id }) else { return }
            openHeroID = "preview-\(id)"
            openGame = game
        }
        // Let the backdrop run under the title bar so the window reads as one surface.
        .toolbarBackground(.hidden, for: .windowToolbar)
        .tint(.overcrossAccent)
        .preferredColorScheme(.dark)
    }

    private var subtitle: String {
        guard openGame == nil else { return "" }
        if store.phase == .loading { return String(localized: "Updating…") }
        let count = store.games.count
        return count == 0 ? "" : String(localized: "\(count) games")
    }

    private func finishSteamLink() async {
        isLinking = true
        defer { isLinking = false }
        await store.refresh()
        linkError = store.phase == .ready ? nil : String(localized: "Steam didn’t confirm the link. Try again.")
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
            ProgressView("Loading your Steam library…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case (.failed(let error), true):
            ContentUnavailableView {
                Label("Library Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.message)
            } actions: {
                Button("Try Again") { Task { await store.refresh() } }
                Button("Link Steam…") { showsSteamLogin = true }
            }
        case (.ready, true):
            ContentUnavailableView("No Games", systemImage: "gamecontroller",
                                   description: Text("This Steam account has no games yet."))
        default:
            library
        }
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if case .failed(let error) = store.phase { staleBanner(error) }

                ForEach(shelves, id: \.title) { shelf in
                    let width: CGFloat = shelf.isLarge ? 380 : 250
                    Shelf(title: shelf.title, games: shelf.games, tileWidth: width) { game in
                        tile(game, width: width, section: shelf.title)
                    }
                }

                // The grid only adds something when the shelves do not already show every game.
                if !search.isEmpty || Set(shelves.flatMap { $0.games.map(\.id) }).count < filtered.count {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(search.isEmpty ? "All Games" : "Search Results")
                            .font(.title3.weight(.semibold))
                        if filtered.isEmpty {
                            Text("No game matches “\(search)”.").foregroundStyle(.secondary)
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
                    Text("Showing the library as of \(lastUpdated.formatted(date: .abbreviated, time: .shortened)).")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            Spacer()
            if error == .notSignedIn {
                Button("Link Again") { showsSteamLogin = true }
            } else {
                Button("Try Again") { Task { await store.refresh() } }
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
                Button(action: close) { Label("Library", systemImage: "chevron.left") }
                    .keyboardShortcut(.cancelAction)
                    .help("Back to Library")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if openGame == nil && !store.games.isEmpty { LibrarySearchField(text: $search) }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if openGame == nil && !store.games.isEmpty {
                Menu {
                    Button("Add Windows Game…") { showsImporter = true }
                    if !store.hasAccount { Button("Link Steam…") { showsSteamLogin = true } }
                    Divider()
                    Button("GOG (Coming Soon)") {}.disabled(true)
                    Button("Epic Games (Coming Soon)") {}.disabled(true)
                    Button("itch.io (Coming Soon)") {}.disabled(true)
                } label: {
                    Label("Add Games", systemImage: "plus")
                }
                .help("Add Games")
            }
            if store.hasAccount && openGame == nil {
                Button { Task { await store.refresh() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.phase == .loading)
                .help("Reload Library from Steam")
                Menu {
                    Button("Link Another Steam Account…") {
                        Task {
                            await store.signOut()
                            showsSteamLogin = true
                        }
                    }
                    Button("Unlink Steam", role: .destructive) { Task { await store.signOut() } }
                } label: {
                    Label("Steam Account", systemImage: "person.crop.circle")
                }
            }
        }
    }
}

/// A row of games that pages with arrow buttons, like shelves in Mac apps. The row ignores the scroll wheel,
/// so scrolling over it always moves the page.
private struct Shelf<Tile: View>: View {
    let title: String
    let games: [LibraryGame]
    let tileWidth: CGFloat
    @ViewBuilder let tile: (LibraryGame) -> Tile

    @State private var leadingID: Int?
    @State private var visibleCount = 1

    private let spacing: CGFloat = 16
    private let margin: CGFloat = 32
    private var leadingIndex: Int { games.firstIndex { $0.id == leadingID } ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                if games.count > visibleCount {
                    HStack(spacing: 8) {
                        Button { page(-1) } label: { Image(systemName: "chevron.left") }
                            .disabled(leadingIndex == 0)
                            .help("Back")
                        Button { page(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(leadingIndex + visibleCount >= games.count)
                            .help("Next")
                    }
                    .buttonStyle(CircleIconButtonStyle(size: 30))
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, margin)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(games) { game in tile(game).id(game.id) }
                }
                .scrollTargetLayout()
                .padding(.vertical, 10)
            }
            .contentMargins(.horizontal, margin, for: .scrollContent)
            .scrollPosition(id: $leadingID, anchor: .leading)
            .scrollDisabled(true)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                visibleCount = max(1, Int((width - 2 * margin + spacing) / (tileWidth + spacing)))
            }
        }
        .animation(.snappy, value: games.count > visibleCount)
    }

    /// Moves by a full row of games, stopping where the last game is fully visible.
    private func page(_ direction: Int) {
        let target = min(max(leadingIndex + direction * visibleCount, 0), max(games.count - visibleCount, 0))
        withAnimation(.smooth(duration: 0.5)) { leadingID = games[target].id }
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
    @Environment(GameRunner.self) private var runner

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                GameCover(game: game, cornerRadius: 10)
                    .saturation(game.isUnsupported ? 0 : 1)
                    .overlay(alignment: .topLeading) { activityBadge }
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
                    if game.isInstalled { Label("Installed", systemImage: "internaldrive").font(.caption) }
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
            TextField("Search Library", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand { text = ""; isFocused = false }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.6))
                    .help("Clear Search")
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
            Button("Search") { isFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }
}

extension ShelfTile {
    @ViewBuilder fileprivate var activityBadge: some View {
        if let activity = runner.activity(for: game) {
            HStack(spacing: 6) {
                switch activity {
                case .running:
                    Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.green).symbolEffect(.pulse)
                    Text("Running")
                case .starting:
                    ProgressView().controlSize(.mini)
                    Text("Starting…")
                case .stopping:
                    ProgressView().controlSize(.mini)
                    Text("Quitting…")
                case .installing:
                    ProgressView().controlSize(.mini)
                    Text("Installing…")
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(8)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }
}
