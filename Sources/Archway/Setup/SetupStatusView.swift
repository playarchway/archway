import SwiftUI

/// A small toolbar capsule while Archway sets itself up in the background. The details live in a popover,
/// so the library stays usable; the capsule disappears once everything is ready.
struct SetupStatusButton: View {
    @Environment(SetupModel.self) private var setup
    @State private var showsDetails = false

    var body: some View {
        if !setup.isReady {
            Button { showsDetails.toggle() } label: {
                HStack(spacing: 7) {
                    indicator
                    Text(title).font(.callout)
                }
                .padding(.horizontal, 4)
            }
            .help("Show Setup Progress")
            .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                SetupDetails().environment(setup)
            }
        }
    }

    private var needsAttention: Bool {
        switch setup.phase {
        case .needsRosetta, .needsSteamQuit, .failed: true
        default: false
        }
    }

    private var title: String {
        if setup.runtimeUpdate != nil {
            return needsAttention ? String(localized: "Update Paused") : String(localized: "Updating…")
        }
        return needsAttention ? String(localized: "Setup Paused") : String(localized: "Setting Up…")
    }

    @ViewBuilder private var indicator: some View {
        if needsAttention {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        } else if let progress = setup.progress {
            ProgressView(value: progress).progressViewStyle(.circular).controlSize(.small)
        } else {
            ProgressView().controlSize(.small)
        }
    }
}

private struct SetupDetails: View {
    @Environment(SetupModel.self) private var setup

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                if let update = setup.runtimeUpdate {
                    Text("Updating Windows Support").font(.headline)
                    Text("Archway installs a new version of its Windows runtime, a \(ByteCountFormatter.string(fromByteCount: update.size, countStyle: .file)) download. You can keep browsing your library.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Setting Up Archway").font(.headline)
                    Text("Archway prepares Windows support in the background. You can keep browsing your library.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            SetupChecklist()
            footer
        }
        .padding(18)
        .frame(width: 320)
    }

    @ViewBuilder private var footer: some View {
        switch setup.phase {
        case .needsRosetta:
            VStack(alignment: .leading, spacing: 8) {
                Text("Windows games need Rosetta. macOS asks for your password to install it.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Install Rosetta") { setup.installRosetta() }
                    .buttonStyle(.borderedProminent)
            }
        case .needsSteamQuit:
            VStack(alignment: .leading, spacing: 8) {
                Text("Windows Steam still runs on the old runtime. Quit it, and any game running in it, to finish the update.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Quit Steam") { setup.quitSteam() }
                    .buttonStyle(.borderedProminent)
            }
        case .failed(_, let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { setup.start() }
            }
        default:
            EmptyView()
        }
    }
}

/// The setup steps with their state, in the popover and in the introduction.
struct SetupChecklist: View {
    var axis: Axis = .vertical

    var body: some View {
        let layout = axis == .vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                                       : AnyLayout(HStackLayout(spacing: 22))
        layout {
            ForEach(SetupModel.Step.allCases, id: \.self) { step in
                StepRow(step: step)
            }
        }
    }
}

private struct StepRow: View {
    @Environment(SetupModel.self) private var setup
    let step: SetupModel.Step

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .foregroundStyle(isCurrent || setup.isDone(step) ? .primary : .secondary)
                if isCurrent, let progress = setup.progress {
                    ProgressView(value: progress).controlSize(.small)
                }
            }
        }
        .animation(.snappy, value: setup.phase)
    }

    private var isCurrent: Bool {
        switch setup.phase {
        case .working(let current), .failed(let current, _): current == step
        case .needsRosetta: step == .rosetta
        case .needsSteamQuit: step == .runtime
        default: false
        }
    }

    @ViewBuilder private var icon: some View {
        if setup.isDone(step) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.archwayAccent)
                .transition(.scale.combined(with: .opacity))
        } else if case .failed(let current, _) = setup.phase, current == step {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        } else if case .needsRosetta = setup.phase, step == .rosetta {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        } else if case .needsSteamQuit = setup.phase, step == .runtime {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        } else if isCurrent {
            ProgressView().controlSize(.mini)
        } else {
            Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }
}
