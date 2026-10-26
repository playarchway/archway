import SwiftUI
import ArchwayCore

/// One game's page: the game itself, whether it runs, and your progress. Technical settings stay behind "Advanced".
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
    /// The bloom's blurred mask is costly, so it goes once the artwork is fully revealed.
    @State private var isRevealComplete = false
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
            withAnimation(reduceMotion ? nil : .easeOut(duration: 1.1)) { isRevealed = true } completion: {
                isRevealComplete = true
            }
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

    /// Fades the artwork out over its lower half so it melts into the page instead of ending at an edge.
    private var heroFade: some View {
        LinearGradient(stops: [.init(color: .black, location: 0),
                               .init(color: .black, location: 0.3),
                               .init(color: .black.opacity(0.8), location: 0.5),
                               .init(color: .black.opacity(0.45), location: 0.7),
                               .init(color: .black.opacity(0.15), location: 0.87),
                               .init(color: .clear, location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// Grows from the cover until it covers the whole artwork.
    private var revealBloom: some View {
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
            .mask {
                if isRevealComplete { heroFade } else { heroFade.mask { revealBloom } }
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
            } else if let note = runner.session(for: game)?.installNote {
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
                            switch runner.session(for: game)?.installPhase {
                            case .downloading?:
                                let progress = runner.session(for: game)?.installProgress ?? 0
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
