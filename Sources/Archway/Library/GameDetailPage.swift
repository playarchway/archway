import SwiftUI
import ArchwayCore

/// One game's page: the game itself, whether it runs, and your progress. Technical settings stay behind "Erweitert".
struct GameDetailPage: View {
    let game: LibraryGame
    let heroNamespace: Namespace.ID
    let heroID: String
    /// Offered for games added from a local .exe.
    var onRemove: (() -> Void)?

    @State private var details: SteamStoreDetails?
    /// Shown once fully loaded, so the page never swaps from a smaller header to the real artwork.
    @State private var backdrop: NSImage?
    @State private var loadFailed = false
    @State private var hasAppeared = false
    /// Drives the artwork's slow drift, so the page never looks frozen.
    @State private var isDrifting = false
    /// Opening a game blooms its artwork outward from the cover.
    @State private var isRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAdvanced = false
    @State private var confirmsUninstall = false
    @State private var enlargedScreenshot: SteamStoreDetails.Screenshot?
    @Environment(\.openURL) private var openURL
    @Environment(GameRunner.self) private var runner
    @Environment(CompatibilityStore.self) private var compatibility
    @Environment(SetupModel.self) private var setup

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
                        compatibilityCard
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
        .scrollIndicators(.never)
        .ignoresSafeArea(edges: .top)
        // No background of its own: the library's ambient backdrop of the same game stays underneath,
        // so opening a game never passes through black.
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.18)) { hasAppeared = true }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 1.1)) { isRevealed = true }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 28).repeatForever(autoreverses: true)) { isDrifting = true }
            }
        }
        .task(id: game.id) { if !game.isLocal { await load() } }
        .task(id: game.id) {
            if let cached = ArtworkLoader.shared.cachedBackdrop(for: game) { backdrop = cached; return }
            let image = await ArtworkLoader.shared.backdrop(for: game)
            withAnimation(.easeOut(duration: 0.7)) { backdrop = image }
        }
        .sheet(isPresented: $showsAdvanced) { AdvancedSettingsSheet(game: game) }
        .confirmationDialog("Uninstall “\(game.title)”?", isPresented: $confirmsUninstall) {
            Button("Uninstall", role: .destructive) { runner.uninstall(game) }
        } message: {
            Text("Saves in the Steam Cloud stay. You can install the game again at any time.")
        }
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
            ZStack {
                HeroPlaceholder(tint: game.tint)
                // Read the cache directly too, so a preloaded image is there from the first frame.
                if let backdrop = backdrop ?? ArtworkLoader.shared.cachedBackdrop(for: game) {
                    Image(nsImage: backdrop).resizable().scaledToFill()
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)), removal: .identity))
                }
            }
            // A slow Ken Burns pan across the artwork.
            .scaleEffect(isDrifting ? 1.1 : 1.05)
            .offset(x: isDrifting ? -20 : 20, y: isDrifting ? -8 : 0)
            .scaleEffect(hasAppeared ? 1 : 1.08)
            // Launching pushes slowly into the artwork; once the game runs it settles slightly enlarged.
            .scaleEffect(launchStage.artworkScale)
            .animation(launchStage == .launching ? .easeInOut(duration: 8) : .smooth(duration: 1.2), value: launchStage)
            // Parallax: the artwork scrolls at half speed and stretches when pulled down.
            .visualEffect { content, proxy in
                let offset = proxy.frame(in: .scrollView).minY
                return content
                    .scaleEffect(offset > 0 ? 1 + offset / 580 : 1, anchor: .bottom)
                    .offset(y: offset < 0 ? -offset * 0.5 : 0)
            }
            .frame(height: 580)
            .frame(maxWidth: .infinity)
            .clipped()
            .blur(radius: isRevealed ? 0 : 24)
            .saturation(game.isUnsupported ? 0 : 1)
            .overlay {
                LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
            }
            // Fade the artwork out over its lower half so it melts into the page instead of ending at an edge.
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.3),
                                       .init(color: .black.opacity(0.8), location: 0.5),
                                       .init(color: .black.opacity(0.45), location: 0.7),
                                       .init(color: .black.opacity(0.15), location: 0.87),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .mask {
                GeometryReader { proxy in
                    // The cover sits bottom left in the centered content column.
                    let cover = CGPoint(x: max(0, (proxy.size.width - 1180) / 2) + 40 + 150, y: proxy.size.height - 78)
                    Circle()
                        .frame(width: 4000, height: 4000)
                        .scaleEffect(isRevealed ? 1 : 0.04)
                        .blur(radius: 80)
                        .position(cover)
                }
            }
            .overlay {
                if launchStage == .launching {
                    LaunchGlow().transition(.opacity.animation(.easeInOut(duration: 0.6)))
                }
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

    private enum LaunchStage: Equatable {
        case idle, launching, running

        var artworkScale: CGFloat {
            switch self {
            case .idle: 1
            case .launching: 1.14
            case .running: 1.06
            }
        }
    }

    private var launchStage: LaunchStage {
        switch runner.activity(for: game) {
        case .starting?: .launching
        case .running?: .running
        default: .idle
        }
    }

    private var byline: String? {
        guard let details else { return nil }
        let year = details.releaseDate?.date.split(separator: " ").last.map(String.init)
        return [details.developers?.first, year].compactMap { $0 }.joined(separator: ", ")
    }

    @ViewBuilder private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            actionButtons
            if !setup.isReady && !game.isUnsupported {
                Text("Available once Archway has finished setting up.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let note = runner.installNotes[game.id] {
                Label(note == .signIn
                      ? String(localized: "Sign in once in the Steam window. The download starts right after.")
                      : String(localized: "The download starts when you quit the running game."),
                      systemImage: note == .signIn ? "person.crop.circle.badge.exclamationmark" : "clock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let error = runner.errors[game.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: runner.activity(for: game))
    }

    @ViewBuilder private var actionButtons: some View {
        HStack(spacing: 10) {
            let activity = runner.activity(for: game)
            if game.isUnsupported {
                EmptyView()
            } else if !game.isInstalled {
                Button { runner.install(game) } label: {
                    HStack(spacing: 10) {
                        if activity == .installing {
                            switch runner.installPhases[game.id] {
                            case .downloading?:
                                let progress = runner.installProgress[game.id] ?? 0
                                ProgressView(value: progress).progressViewStyle(.circular).controlSize(.small)
                                Text("Downloading… \(progress.formatted(.percent.precision(.fractionLength(0))))")
                                    .monospacedDigit()
                            case .installing?:
                                ProgressView().controlSize(.small)
                                Text("Installing…")
                            default:
                                ProgressView().controlSize(.small)
                                Text("Preparing Download…")
                            }
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Install")
                        }
                    }
                }
                .buttonStyle(HeroActionButtonStyle(isBusy: activity == .installing))
                .disabled(activity == .installing || !setup.isReady)
            } else {
                // While the game runs, the button turns into a status; quit from the game itself.
                if runner.uninstalling.contains(game.id) {
                    Button {} label: {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Uninstalling…")
                        }
                    }
                    .buttonStyle(HeroActionButtonStyle(isBusy: true))
                    .disabled(true)
                } else if case .running(let since) = activity {
                    RunningIndicator(since: since)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    PlayButton(activity: activity) { runner.play(game) }
                        .disabled(!setup.isReady)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            Menu {
                if game.isLocal {
                    Button("Show in Finder") { runner.showFolder(game) }
                } else {
                    Button("Open in Steam Store") {
                        openURL(URL(string: "https://store.steampowered.com/app/\(game.id)")!)
                    }
                    if game.isInstalled { Button("Show Game Folder in Finder") { runner.showFolder(game) } }
                }
                Divider()
                if !game.isLocal && game.isInstalled && runner.activity(for: game) == nil {
                    Button("Uninstall…", role: .destructive) { confirmsUninstall = true }
                        .disabled(!runner.canUninstall || runner.uninstalling.contains(game.id))
                    Divider()
                }
                if case .running = runner.activity(for: game) {
                    Button("Quit Game") { runner.stop(game) }
                    Divider()
                }
                Button("Advanced…") { showsAdvanced = true }.disabled(game.isUnsupported)
                if !game.isLocal, runner.lastObservedSessions[game.id] != nil {
                    Button("Report Last Session…") { runner.showFeedback(for: game.id) }
                }
                if let onRemove {
                    Button("Remove from Archway", role: .destructive, action: onRemove)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(CircleIconButtonStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More Actions")
        }
    }

    // MARK: Main column

    @ViewBuilder private var about: some View {
        if !game.isLocal { steamAbout }
    }

    private var steamAbout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About the Game").font(.title3.weight(.semibold))
            if let details {
                Text(details.summary)
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: 640, alignment: .leading)
            } else if loadFailed {
                HStack {
                    Text("The game information couldn’t be loaded from Steam.").foregroundStyle(.secondary)
                    Button("Reload") { Task { await load() } }.buttonStyle(.link)
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
        InfoCard(title: "Your Game") {
            // The status pill already says whether it runs; only the reason why not adds something.
            if game.isUnsupported {
                Text(game.compatibility.explanation).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
            }
            InfoRow("Playtime", game.playtime ?? String(localized: "Not played yet"))
            if let lastPlayed = game.lastPlayed { InfoRow("Recently Played", lastPlayed) }
            if let path = game.executablePath {
                InfoRow("File", URL(fileURLWithPath: path).lastPathComponent)
                if !game.isInstalled { InfoRow("Status", String(localized: "File Not Found")) }
            } else {
                InfoRow("Installed", game.isInstalled ? String(localized: "Yes") : String(localized: "No"))
            }
            if let details {
                InfoRow("Saves", details.hasCloudSaves ? String(localized: "In Steam Cloud") : String(localized: "On This Mac"))
            }
        }
    }

    private var compatibilityCard: some View {
        InfoCard(title: "Community Compatibility") {
            if compatibility.catalog == nil {
                Text("No community catalog cached yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(CompatibilityMode.allCases, id: \.self) { mode in
                    let aggregates = compatibility.aggregates(for: game.id, mode: mode)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode == .singleplayer ? "Singleplayer" : "Multiplayer").font(.callout.weight(.medium))
                        if let aggregate = aggregates.first {
                            ForEach(CompatibilityOutcome.allCases, id: \.self) { outcome in
                                if let count = aggregate.counts[outcome], count > 0 {
                                    InfoRow(LocalizedStringKey(outcome.label), String(count))
                                }
                            }
                            if mode == .multiplayer {
                                ForEach(MultiplayerFeature.allCases, id: \.self) { feature in
                                    if let counts = aggregate.features[feature], !counts.isEmpty {
                                        let summary = CompatibilityOutcome.allCases.compactMap { outcome in
                                            counts[outcome].map { "\(outcome.label): \($0)" }
                                        }.joined(separator: ", ")
                                        Text("\(feature.label): \(summary)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } else {
                            Text("Not Tested for this configuration").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                let currentContext = compatibility.context(for: game.id)
                let other = compatibility.catalog?.aggregates.filter { $0.gameID == game.id &&
                    $0.context != currentContext } ?? []
                if !other.isEmpty {
                    Text("Reports for other configurations")
                        .font(.callout.weight(.medium))
                    ForEach(Array(other.prefix(5).enumerated()), id: \.offset) { _, aggregate in
                        DisclosureGroup {
                            ForEach(CompatibilityOutcome.allCases, id: \.self) { outcome in
                                if let count = aggregate.counts[outcome], count > 0 {
                                    InfoRow(LocalizedStringKey(outcome.label), String(count))
                                }
                            }
                            InfoRow("Wine runtime", aggregate.context.runtimeVersion)
                            InfoRow("App version", aggregate.context.appVersion)
                            InfoRow("macOS", aggregate.context.macOSVersion)
                            InfoRow("Game build", aggregate.context.gameVersion)
                            InfoRow("Graphics backend", aggregate.context.graphicsBackend)
                            InfoRow("Launch arguments", aggregate.context.profile.launchArguments.joined(separator: " "))
                        } label: {
                            Text("\(aggregate.mode == .singleplayer ? String(localized: "Singleplayer") : String(localized: "Multiplayer")) · \(aggregate.context.chip)")
                                .font(.caption)
                        }
                    }
                }
                Text("Counts match this runtime, macOS, chip, game build, graphics backend, and saved game settings. Reports from this Mac are not counted until the community catalog includes them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            let own = compatibility.submittedReports.filter { $0.gameID == game.id }.count
            if own > 0 {
                Text("\(own) report(s) from this Mac, shown separately")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(compatibility.submittedReports.filter { $0.gameID == game.id }.suffix(3)) { report in
                    Text("\(report.mode == .singleplayer ? String(localized: "Singleplayer") : String(localized: "Multiplayer")): \(report.outcome.label)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            let pendingCount = compatibility.pendingReports.filter { $0.gameID == game.id }.count
            if pendingCount > 0 {
                Text("\(pendingCount) report(s) saved locally")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Retry Sending") { Task { await compatibility.retryPending() } }.buttonStyle(.link)
            }
            if let error = compatibility.lastSubmissionError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private var facts: some View {
        if let details {
            InfoCard(title: "Details") {
                if let developer = details.developers?.joined(separator: ", ") { InfoRow("Developer", developer) }
                if let publisher = details.publishers?.joined(separator: ", "), publisher != details.developers?.joined(separator: ", ") {
                    InfoRow("Publisher", publisher)
                }
                if let date = details.releaseDate?.date { InfoRow("Released", date) }
                if let genres = details.genres?.map(\.description).joined(separator: ", ") { InfoRow("Genre", genres) }
                if let total = details.achievements?.total { InfoRow("Achievements", "\(total)") }
                if details.controllerSupport == "full" { InfoRow("Controller", String(localized: "Full Support")) }
            }
        }
    }

    @ViewBuilder private var features: some View {
        if let features = details?.features, !features.isEmpty {
            InfoCard(title: "Features") {
                FlowLayout(spacing: 6) {
                    ForEach(features, id: \.self) { feature in
                        Text(feature)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.white.opacity(0.08), in: Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - Building blocks

private struct PlayButton: View {
    let activity: GameRunner.Activity?
    let action: () -> Void

    private var isBusy: Bool { activity == .starting || activity == .stopping }

    private var title: String {
        switch activity {
        case .starting: String(localized: "Starting…")
        case .stopping: String(localized: "Quitting…")
        default: String(localized: "Play")
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.fill")
                }
                Text(title).contentTransition(.interpolate)
            }
            .frame(minWidth: 150)
        }
        .buttonStyle(HeroActionButtonStyle(isBusy: isBusy))
        .disabled(isBusy)
    }
}

/// The page's main action: a large amber capsule that brightens on hover and presses in on click.
struct HeroActionButtonStyle: ButtonStyle {
    static let height: CGFloat = 48
    var isBusy = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        HoverableCapsule(configuration: configuration, isBusy: isBusy)
    }

    private struct HoverableCapsule: View {
        let configuration: ButtonStyleConfiguration
        let isBusy: Bool
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.title3.weight(.bold))
                .foregroundStyle(isBusy ? Color.white : Color.black)
                .padding(.horizontal, 26)
                .frame(height: HeroActionButtonStyle.height)
                .background {
                    Capsule().fill(isBusy ? Color.white.opacity(0.16) : Color.archwayAccent)
                        .overlay(Capsule().fill(.white.opacity(isHovered && !isBusy ? 0.15 : 0)))
                }
                .shadow(color: Color.archwayAccent.opacity(isBusy ? 0 : (isHovered ? 0.55 : 0.35)),
                        radius: isHovered ? 18 : 12, y: 4)
                .scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.02 : 1))
                .animation(.snappy(duration: 0.18), value: isHovered)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }
    }
}

/// The game's color, slowly breathing while its artwork loads.
private struct HeroPlaceholder: View {
    let tint: Color

    var body: some View {
        PhaseAnimator([false, true]) { bright in
            RadialGradient(colors: [tint.opacity(bright ? 0.6 : 0.35), tint.opacity(0.1), .clear],
                           center: UnitPoint(x: 0.6, y: 0.3), startRadius: 0, endRadius: bright ? 900 : 700)
        } animation: { _ in
            .easeInOut(duration: 1.6)
        }
    }
}

/// An amber glow that breathes behind the play button while the game starts.
private struct LaunchGlow: View {
    var body: some View {
        PhaseAnimator([0.4, 0.8]) { intensity in
            RadialGradient(colors: [Color.archwayAccent.opacity(0.4), Color.archwayAccent.opacity(0.12), .clear],
                           center: UnitPoint(x: 0.35, y: 0.85), startRadius: 0, endRadius: 700)
                .opacity(intensity)
        } animation: { _ in
            .easeInOut(duration: 2)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

/// A round, secondary action beside the main button; the whole circle is clickable.
struct CircleIconButtonStyle: ButtonStyle {
    var size: CGFloat = HeroActionButtonStyle.height

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        HoverableCircle(configuration: configuration, size: size)
    }

    private struct HoverableCircle: View {
        let configuration: ButtonStyleConfiguration
        let size: CGFloat
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.35))
                .frame(width: size, height: size)
                .background(.white.opacity(isHovered ? 0.22 : 0.14), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18)))
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .animation(.snappy(duration: 0.15), value: isHovered)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }
    }
}

/// Takes the play button's place while the game runs: a live "running for" counter with a pulsing dot.
private struct RunningIndicator: View {
    let since: Date

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.green)
                .symbolEffect(.pulse)
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text("Running for \(Duration.seconds(context.date.timeIntervalSince(since)).formatted(.time(pattern: .minuteSecond)))")
                    .monospacedDigit()
            }
        }
        .font(.title3.weight(.semibold))
        .padding(.horizontal, 22)
        .frame(minWidth: 150, minHeight: HeroActionButtonStyle.height)
        .background(Color.green.opacity(0.18), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.green.opacity(0.35)))
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
    let title: LocalizedStringKey
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
    let label: LocalizedStringKey
    let value: String

    init(_ label: LocalizedStringKey, _ value: String) {
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
                Text("\(index + 1) of \(screenshots.count)").foregroundStyle(.secondary).frame(width: 90)
                Button { current = screenshots[index + 1] } label: { Image(systemName: "chevron.right") }
                    .disabled(index >= screenshots.count - 1)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
    }
}

/// The technical choices for one game, out of the way of the normal page.
private struct AdvancedSettingsSheet: View {
    let game: LibraryGame
    @State private var launchArguments: String
    @State private var graphicsAPI: GameGraphicsAPIChoice
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(GameRunner.self) private var runner
    @Environment(CompatibilityStore.self) private var compatibility

    init(game: LibraryGame) {
        self.game = game
        _launchArguments = State(initialValue: "")
        _graphicsAPI = State(initialValue: .gameDefault)
    }

    private var logURL: URL? { runner.logURL(for: game) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Advanced Settings").font(.title3.weight(.semibold))
            Text("Saved for this game. Supported options depend on the game.")
                .font(.callout).foregroundStyle(.secondary)
            Form {
                LabeledContent("Graphics backend", value: compatibility.context(for: game.id).graphicsBackend)
                Text("The graphics backend belongs to the shared Steam environment and cannot be changed for one game here.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Game launch arguments (one per line)", text: $launchArguments, axis: .vertical)
                    .lineLimit(3...7)
                if game.id == 5_228_920 {
                    Picker("Graphics API", selection: $graphicsAPI) {
                        Text("Game Default").tag(GameGraphicsAPIChoice.gameDefault)
                        Text("Direct3D 11").tag(GameGraphicsAPIChoice.d3d11)
                        Text("Direct3D 12").tag(GameGraphicsAPIChoice.d3d12)
                    }
                }
                LabeledContent("Last Launch") {
                    Button("Export Log…", action: exportLog).disabled(logURL == nil)
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Restore Defaults") { launchArguments = ""; graphicsAPI = .gameDefault }
                Spacer()
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.orange) }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            let profile = compatibility.profile(for: game.id)
            launchArguments = profile.launchArguments.joined(separator: "\n")
            graphicsAPI = profile.graphicsAPI
        }
    }

    private func save() {
        let arguments = launchArguments.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        do {
            try compatibility.save(GameRuntimeProfile(launchArguments: arguments, graphicsAPI: graphicsAPI), for: game.id)
            dismiss()
        } catch {
            saveError = String(localized: "Use up to 12 arguments, one per line, at most 100 characters each.")
        }
    }

    private func exportLog() {
        guard let logURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Archway \(game.title).log"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: logURL, to: destination)
    }
}
