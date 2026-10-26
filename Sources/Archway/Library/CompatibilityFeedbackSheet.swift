import SwiftUI
import ArchwayCore

/// Asks how a game ran after it closed. One click answers the question; everything else is optional.
struct CompatibilityFeedbackSheet: View {
    let session: GameRunner.CompletedGameSession
    let compatibility: CompatibilityStore
    let onClose: () -> Void

    @State private var outcome: CompatibilityOutcome?
    @State private var mode: CompatibilityMode = .singleplayer
    @State private var features: [MultiplayerFeature: CompatibilityOutcome] = [:]
    @State private var issue: CompatibilityIssue?
    @State private var note = ""
    @State private var optOut = false
    @State private var artwork: NSImage?
    @State private var showsMultiplayerDetails = false
    @State private var showsSentFields = false

    private static let ratings: [CompatibilityOutcome] = [.works, .limited, .unplayable]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    ForEach(Self.ratings, id: \.self) { rating in
                        RatingButton(outcome: rating, isSelected: outcome == rating) {
                            withAnimation(.snappy(duration: 0.2)) { outcome = rating }
                        }
                    }
                }
                if outcome != nil { details.transition(.opacity) }
            }
            .padding(20)
            Divider()
            footer.padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(SheetFitsContent())
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let artwork { Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill) } else { session.game.tint }
            }
            .frame(height: 130)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 3) {
                Text("How did \(session.game.title) run?").font(.title2.weight(.semibold))
                Text("Your answer helps other Mac players with the same setup.")
                    .font(.callout).foregroundStyle(.white.opacity(0.75))
            }
            .padding(20)
        }
        .task { artwork = await ArtworkLoader.shared.backdrop(for: session.game) }
    }

    @ViewBuilder private var details: some View {
        Picker("Played", selection: $mode) {
            Text("Singleplayer").tag(CompatibilityMode.singleplayer)
            Text("Multiplayer").tag(CompatibilityMode.multiplayer)
        }
        .pickerStyle(.segmented)
        .fixedSize()

        if mode == .multiplayer {
            DisclosureGroup(isExpanded: $showsMultiplayerDetails) {
                VStack(spacing: 6) {
                    ForEach(MultiplayerFeature.allCases, id: \.self) { feature in
                        FeatureRow(feature: feature, outcome: $features[feature])
                    }
                }
                .padding(.top, 8)
            } label: {
                ToggleLabel(title: "Multiplayer details (optional)", isExpanded: $showsMultiplayerDetails)
            }
        }

        if outcome == .limited || outcome == .unplayable {
            VStack(alignment: .leading, spacing: 8) {
                Text("What was the problem?").font(.callout.weight(.medium))
                HStack(spacing: 6) {
                    ForEach(CompatibilityIssue.allCases, id: \.self) { item in
                        Chip(label: item.label, isSelected: issue == item) { issue = issue == item ? nil : item }
                    }
                }
            }
        }

        TextField("Anything else? (optional)", text: $note, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(2...4)
            .padding(10)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.1)))
            .onChange(of: note) { _, value in if value.count > 500 { note = String(value.prefix(500)) } }

        Button { showsSentFields = true } label: {
            Label("What gets sent?", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsSentFields, arrowEdge: .top) { sentFieldsPopover }
    }

    private var sentFieldsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                ForEach(sentFields, id: \.0) { label, value in
                    GridRow {
                        Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Text(value).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                }
            }
            Text("Your answers, this configuration, and the time of the report. No Steam account, game path, logs, or playtime.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .padding(16)
        .frame(width: 340)
    }

    private var footer: some View {
        HStack {
            Toggle("Don’t ask again", isOn: $optOut).toggleStyle(.checkbox)
            Spacer()
            Button("Skip") { close() }.keyboardShortcut(.cancelAction)
            Button("Send") { submit() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(outcome == nil)
        }
    }

    private var sentFields: [(String, String)] {
        let context = session.context
        let arguments = context.profile.launchArguments.joined(separator: " ")
        var fields = [
            (String(localized: "Game ID"), String(session.game.id)),
            (String(localized: "Archway version"), context.appVersion),
            (String(localized: "Wine runtime"), context.runtimeVersion),
            (String(localized: "macOS"), context.macOSVersion),
            (String(localized: "Chip"), context.chip),
            (String(localized: "Game build"), context.gameVersion),
            (String(localized: "Graphics backend"), context.graphicsBackend),
            (String(localized: "Launch arguments"), arguments.isEmpty ? String(localized: "None") : arguments),
        ]
        if session.game.id == Orchestrator.firstAppID {
            fields.append((String(localized: "Graphics API"), context.profile.graphicsAPI.label))
        }
        return fields
    }

    private func submit() {
        guard let outcome else { return }
        let report = CompatibilityReport(gameID: session.game.id, mode: mode, outcome: outcome, features: features,
                                         issue: outcome == .works ? nil : issue, note: note.isEmpty ? nil : note,
                                         context: session.context)
        Task { await compatibility.submit(report) }
        close()
    }

    private func close() {
        if optOut { UserDefaults.standard.set(true, forKey: "disableCompatibilityFeedback") }
        onClose()
    }
}

/// Resizes the sheet's window to the content's height; SwiftUI keeps a sheet at its first size.
private struct SheetFitsContent: ViewModifier {
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .background(WindowHeight(height: height))
    }

    private struct WindowHeight: NSViewRepresentable {
        let height: CGFloat

        func makeNSView(context: Context) -> NSView { NSView() }

        func updateNSView(_ view: NSView, context: Context) {
            guard height > 0, let window = view.window else { return }
            var frame = window.frame
            let delta = height - window.contentRect(forFrameRect: frame).height
            guard abs(delta) > 0.5 else { return }
            frame.origin.y -= delta
            frame.size.height += delta
            window.setFrame(frame, display: true, animate: true)
        }
    }
}

/// One of the three large answers to "How did it run?".
private struct RatingButton: View {
    let outcome: CompatibilityOutcome
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: outcome.symbol).font(.title2)
                    .foregroundStyle(outcome.color.opacity(isSelected ? 1 : 0.7))
                Text(outcome.label).font(.callout.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background(isSelected ? outcome.color.opacity(0.16) : .white.opacity(isHovered ? 0.08 : 0.04),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? outcome.color : .white.opacity(0.1), lineWidth: isSelected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A multiplayer feature with three small answers; clicking the chosen one again clears it.
private struct FeatureRow: View {
    let feature: MultiplayerFeature
    @Binding var outcome: CompatibilityOutcome?

    var body: some View {
        HStack {
            Text(feature.label).font(.callout)
            Spacer()
            HStack(spacing: 4) {
                ForEach([CompatibilityOutcome.works, .limited, .unplayable], id: \.self) { item in
                    Button { outcome = outcome == item ? nil : item } label: {
                        Image(systemName: item.symbol)
                            .foregroundStyle(item.color.opacity(outcome == item ? 1 : 0.45))
                            .frame(width: 30, height: 24)
                            .background(outcome == item ? item.color.opacity(0.16) : .white.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(item.label)
                }
            }
        }
    }
}

/// A disclosure label that opens on a click anywhere on its text, not only on the chevron.
private struct ToggleLabel: View {
    let title: LocalizedStringKey
    @Binding var isExpanded: Bool

    var body: some View {
        Button(title) { withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() } }
            .buttonStyle(.plain)
    }
}

private struct Chip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label).font(.callout)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(isSelected ? Color.archwayAccent.opacity(0.2) : .white.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Color.archwayAccent : .white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

extension CompatibilityOutcome {
    var label: String {
        switch self {
        case .works: String(localized: "Works")
        case .limited: String(localized: "Limited")
        case .unplayable: String(localized: "Unplayable")
        case .notTested: String(localized: "Not Tested")
        }
    }

    var symbol: String {
        switch self {
        case .works: "checkmark.circle.fill"
        case .limited: "exclamationmark.triangle.fill"
        case .unplayable: "xmark.octagon.fill"
        case .notTested: "circle.dashed"
        }
    }

    var color: Color {
        switch self {
        case .works: .green
        case .limited: .orange
        case .unplayable: .red
        case .notTested: .secondary
        }
    }
}

extension GameGraphicsAPIChoice {
    var label: String {
        switch self {
        case .gameDefault: String(localized: "Game Default")
        case .d3d11: "Direct3D 11"
        case .d3d12: "Direct3D 12"
        }
    }
}

extension MultiplayerFeature {
    var label: String {
        switch self {
        case .join: String(localized: "Join games")
        case .host: String(localized: "Host games")
        case .invites: String(localized: "Invites")
        case .crossplay: String(localized: "Crossplay")
        case .voice: String(localized: "Voice chat")
        case .disconnects: String(localized: "Connection stability")
        }
    }
}

extension CompatibilityIssue {
    var label: String {
        switch self {
        case .start: String(localized: "Game start")
        case .graphics: String(localized: "Graphics")
        case .audio: String(localized: "Audio")
        case .performance: String(localized: "Performance")
        case .network: String(localized: "Network")
        }
    }
}
