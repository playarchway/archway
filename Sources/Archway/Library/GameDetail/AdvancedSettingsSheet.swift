import SwiftUI
import ArchwayCore

/// The technical choices for one game, out of the way of the normal page.
struct AdvancedSettingsSheet: View {
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
                Picker("Graphics API", selection: $graphicsAPI) {
                    Text("Game Default").tag(GameGraphicsAPIChoice.gameDefault)
                    Text("Direct3D 11").tag(GameGraphicsAPIChoice.d3d11)
                    Text("Direct3D 12").tag(GameGraphicsAPIChoice.d3d12)
                }
                Text("Only games made with Unity follow this setting.")
                    .font(.caption).foregroundStyle(.secondary)
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
