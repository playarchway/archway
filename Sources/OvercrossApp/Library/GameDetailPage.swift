import SwiftUI

/// One game's page: the game itself, whether it runs, and your progress. Technical settings stay behind "Erweitert".
struct GameDetailPage: View {
    let game: LibraryGame
    let heroNamespace: Namespace.ID
    let heroID: String
    /// Offered for games added from a local .exe.
    var onRemove: (() -> Void)?

    @State private var details: SteamStoreDetails?
    @State private var loadFailed = false
    @State private var runningSince: Date?
    @State private var hasAppeared = false
    @State private var showsAdvanced = false
    @State private var enlargedScreenshot: SteamStoreDetails.Screenshot?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                HStack(alignment: .top, spacing: 36) {
                    VStack(alignment: .leading, spacing: 30) {
                        about
                        screenshots
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 18) {
                        yourGame
                        facts
                        features
                    }
                    .frame(width: 320)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 32)
                .frame(maxWidth: 1180, alignment: .leading)
                .frame(maxWidth: .infinity)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 28)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.black)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.18)) { hasAppeared = true }
        }
        .task(id: game.id) { if !game.isLocal { await load() } }
        .sheet(isPresented: $showsAdvanced) { AdvancedSettingsSheet(game: game) }
        .sheet(item: $enlargedScreenshot) { shot in
            ScreenshotViewer(screenshots: details?.screenshots ?? [], current: shot)
        }
    }

    private func load() async {
        loadFailed = false
        do { details = try await SteamStoreClient.shared.details(for: game.id) } catch { loadFailed = true }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: details?.backgroundRaw ?? game.headerURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    game.tint
                }
            }
            .scaleEffect(hasAppeared ? 1 : 1.08)
            .opacity(hasAppeared ? 1 : 0)
            .frame(height: 420)
            .frame(maxWidth: .infinity)
            .clipped()
            .saturation(game.isUnsupported ? 0 : 1)
            .overlay {
                LinearGradient(stops: [.init(color: .black.opacity(0.15), location: 0),
                                       .init(color: .black.opacity(0.35), location: 0.45),
                                       .init(color: .black, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }

            HStack(alignment: .bottom, spacing: 28) {
                GameCover(game: game, cornerRadius: 12)
                    .saturation(game.isUnsupported ? 0 : 1)
                    .frame(width: 300)
                    .matchedGeometryEffect(id: heroID, in: heroNamespace)
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                VStack(alignment: .leading, spacing: 12) {
                    Text(game.title)
                        .font(.system(size: 36, weight: .bold))
                        .lineLimit(2)
                    if let byline { Text(byline).font(.title3).foregroundStyle(.secondary) }
                    StatusPill(compatibility: game.compatibility)
                    actions.padding(.top, 6)
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(x: hasAppeared ? 0 : -16)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 8)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var byline: String? {
        guard let details else { return nil }
        let year = details.releaseDate?.date.split(separator: " ").last.map(String.init)
        return [details.developers?.first, year].compactMap { $0 }.joined(separator: ", ")
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 10) {
            if game.isUnsupported {
                EmptyView()
            } else if !game.isInstalled {
                Button { } label: {
                    Label("Über Steam installieren", systemImage: "arrow.down.circle").frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
            } else {
                PlayButton(runningSince: $runningSince)
                if let runningSince {
                    RunningIndicator(since: runningSince)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            Menu {
                if game.isLocal {
                    if let path = game.executablePath {
                        Button("Im Finder zeigen") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                    }
                } else {
                    Button("Im Steam-Shop öffnen") {
                        openURL(URL(string: "https://store.steampowered.com/app/\(game.id)")!)
                    }
                    if game.isInstalled { Button("Spielordner im Finder zeigen") {} }
                }
                Divider()
                Button("Erweitert …") { showsAdvanced = true }.disabled(game.isUnsupported)
                if let onRemove {
                    Button("Aus Overcross entfernen", role: .destructive, action: onRemove)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .controlSize(.extraLarge)
            .fixedSize()
        }
    }

    // MARK: Main column

    @ViewBuilder private var about: some View {
        if !game.isLocal { steamAbout }
    }

    private var steamAbout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Über das Spiel").font(.title3.weight(.semibold))
            if let details {
                Text(details.summary)
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: 640, alignment: .leading)
            } else if loadFailed {
                HStack {
                    Text("Die Spielinformationen konnten nicht von Steam geladen werden.").foregroundStyle(.secondary)
                    Button("Erneut laden") { Task { await load() } }.buttonStyle(.link)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder private var screenshots: some View {
        if let shots = details?.screenshots, !shots.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Screenshots").font(.title3.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(shots.prefix(6)) { shot in
                        Button { enlargedScreenshot = shot } label: {
                            AsyncImage(url: shot.pathThumbnail) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() } else { Color.white.opacity(0.06) }
                            }
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Side column

    private var yourGame: some View {
        InfoCard(title: "Dein Spiel") {
            // The status pill already says whether it runs; only the reason why not adds something.
            if game.isUnsupported {
                Text(game.compatibility.explanation).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
            }
            InfoRow("Spielzeit", game.playtime ?? "Noch nicht gespielt")
            if let lastPlayed = game.lastPlayed { InfoRow("Zuletzt gespielt", lastPlayed) }
            if let path = game.executablePath {
                InfoRow("Datei", URL(fileURLWithPath: path).lastPathComponent)
                if !game.isInstalled { InfoRow("Status", "Datei nicht gefunden") }
            } else {
                InfoRow("Installiert", game.isInstalled ? "Ja" : "Nein")
            }
            if let details {
                InfoRow("Spielstände", details.hasCloudSaves ? "In der Steam Cloud" : "Auf diesem Mac")
            }
        }
    }

    @ViewBuilder private var facts: some View {
        if let details {
            InfoCard(title: "Infos") {
                if let developer = details.developers?.joined(separator: ", ") { InfoRow("Entwickler", developer) }
                if let publisher = details.publishers?.joined(separator: ", "), publisher != details.developers?.joined(separator: ", ") {
                    InfoRow("Publisher", publisher)
                }
                if let date = details.releaseDate?.date { InfoRow("Erschienen", date) }
                if let genres = details.genres?.map(\.description).joined(separator: ", ") { InfoRow("Genre", genres) }
                if let total = details.achievements?.total { InfoRow("Errungenschaften", "\(total)") }
                if details.controllerSupport == "full" { InfoRow("Controller", "Volle Unterstützung") }
            }
        }
    }

    @ViewBuilder private var features: some View {
        if let features = details?.features, !features.isEmpty {
            InfoCard(title: "Funktionen") {
                FlowLayout(spacing: 6) {
                    ForEach(features, id: \.self) { feature in
                        Text(feature)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.white.opacity(0.08), in: Capsule())
                    }
                }
                if features.contains(where: { $0.contains("Online") }) {
                    Text("Online-Mehrspieler ist mit Overcross noch nicht getestet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Building blocks

private struct PlayButton: View {
    @Binding var runningSince: Date?

    var body: some View {
        let isRunning = runningSince != nil
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                runningSince = isRunning ? nil : .now
            }
        } label: {
            Label {
                Text(isRunning ? "Beenden" : "Spielen").contentTransition(.interpolate)
            } icon: {
                Image(systemName: isRunning ? "stop.fill" : "play.fill").contentTransition(.symbolEffect(.replace))
            }
            .font(.title3.weight(.semibold))
            .frame(minWidth: 130)
        }
        .buttonStyle(.borderedProminent)
        .tint(isRunning ? Color(white: 0.28) : .overcrossAccent)
        .foregroundStyle(isRunning ? .white : .black)
        .controlSize(.extraLarge)
    }
}

/// A live "running for" counter with a gently pulsing dot.
private struct RunningIndicator: View {
    let since: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.green)
                .symbolEffect(.pulse)
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text("Läuft seit \(Duration.seconds(context.date.timeIntervalSince(since)).formatted(.time(pattern: .minuteSecond)))")
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
        }
    }
}

private struct StatusPill: View {
    let compatibility: LibraryGame.Compatibility

    var body: some View {
        Label(compatibility.headline, systemImage: compatibility.symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(compatibility.color == .secondary ? .primary : compatibility.color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(compatibility.color.opacity(0.18), in: Capsule())
    }
}

private struct InfoCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}

/// Wraps its children onto new lines, like text.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

private struct ScreenshotViewer: View {
    let screenshots: [SteamStoreDetails.Screenshot]
    @State var current: SteamStoreDetails.Screenshot
    @Environment(\.dismiss) private var dismiss

    private var index: Int { screenshots.firstIndex { $0.id == current.id } ?? 0 }

    var body: some View {
        VStack(spacing: 12) {
            AsyncImage(url: current.pathFull) { phase in
                if let image = phase.image { image.resizable().scaledToFit() } else { ProgressView() }
            }
            .frame(width: 960, height: 540)
            HStack {
                Button { current = screenshots[index - 1] } label: { Image(systemName: "chevron.left") }
                    .disabled(index == 0)
                Text("\(index + 1) von \(screenshots.count)").foregroundStyle(.secondary).frame(width: 90)
                Button { current = screenshots[index + 1] } label: { Image(systemName: "chevron.right") }
                    .disabled(index >= screenshots.count - 1)
                Spacer()
                Button("Schließen") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
    }
}

/// The technical choices for one game, out of the way of the normal page.
private struct AdvancedSettingsSheet: View {
    let game: LibraryGame
    @State private var backend: String
    @Environment(\.dismiss) private var dismiss

    init(game: LibraryGame) {
        self.game = game
        _backend = State(initialValue: game.backend)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Erweiterte Einstellungen").font(.title3.weight(.semibold))
            Text("Nur ändern, wenn das Spiel nicht richtig startet.")
                .font(.callout).foregroundStyle(.secondary)
            Form {
                Picker("Grafik", selection: $backend) {
                    ForEach(["D3DMetal", "DXVK", "WineD3D"], id: \.self) { Text($0) }
                }
                LabeledContent("Windows-Umgebung", value: "Steam (Wine 11.17)")
                LabeledContent("Letzter Start") {
                    Button("Protokoll exportieren …") {}.disabled(!game.isInstalled)
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Standard wiederherstellen") { backend = game.backend }
                Spacer()
                Button("Fertig") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
