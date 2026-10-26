import AppKit
import SwiftUI

/// The Dock icons Archway ships with. The glowing arch is the default; the gateway is the bolder alternative.
enum AppIcon: String, CaseIterable, Identifiable {
    case glow, gateway

    static let defaultsKey = "appIcon"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glow: String(localized: "Glowing Arch")
        case .gateway: String(localized: "Gateway")
        }
    }

    var image: NSImage? {
        let name = self == .glow ? "AppIcon" : "AppIcon-Gateway"
        return Bundle.module.url(forResource: name, withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }

    static var current: AppIcon {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(AppIcon.init(rawValue:)) ?? .glow
    }

    @MainActor func apply() { NSApplication.shared.applicationIconImage = image }
}

/// Archway's own settings window (⌘,).
struct AppSettingsView: View {
    let runner: GameRunner?
    let setup: SetupModel?
    let storage: StorageModel?
    let compatibility: CompatibilityStore?
    @AppStorage(AppIcon.defaultsKey) private var icon = AppIcon.glow
    @AppStorage("compatibilityCatalogURL") private var catalogURL = CompatibilityStore.defaultCatalogURL
    @AppStorage("compatibilityReportURL") private var reportURL = CompatibilityStore.defaultReportURL
    @AppStorage("disableCompatibilityFeedback") private var disableFeedback = false
    @State private var confirmsRemoval = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("Open Steam") { runner?.openSteam() }
                        .disabled(setup?.isReady != true)
                } label: {
                    Text("Steam")
                    Text(setup?.isReady == true
                         ? String(localized: "Archway opens Steam only when a game needs it.")
                         : String(localized: "Available once Archway has finished setting up."))
                }
                LabeledContent("GOG, Epic Games, itch.io") {
                    Text("Coming Soon").foregroundStyle(.secondary)
                }
            } header: {
                Text("Game Libraries")
            }
            if let storage {
                Section {
                    LabeledContent("Archway Uses") {
                        if let total = storage.totalBytes {
                            Text(total.formatted(.byteCount(style: .file)))
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if let games = storage.gameBytes, games > 0 {
                        LabeledContent("Installed Games", value: games.formatted(.byteCount(style: .file)))
                    }
                    HStack {
                        Button("Show in Finder") { storage.showInFinder() }
                        Spacer()
                        Button("Remove Archway…", role: .destructive) { confirmsRemoval = true }
                            .disabled(storage.isRemoving)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Moving Archway to the Trash leaves its games and Windows environment on the disk. Remove Archway here to delete everything.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .task { await storage.measure() }
                .alert("Remove Archway and all its data?", isPresented: $confirmsRemoval) {
                    Button("Remove Archway", role: .destructive) { Task { await storage.removeArchway() } }
                } message: {
                    Text("This deletes the Windows environment, Windows Steam, and every game installed in Archway. Saves in the Steam Cloud stay; saves kept only on this Mac are lost. Archway then moves itself to the Trash.")
                }
            }
            Section("App Icon") {
                HStack(spacing: 20) {
                    ForEach(AppIcon.allCases) { option in
                        IconChoice(icon: option, isSelected: option == icon) { icon = option }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("Compatibility Reports") {
                DisclosureGroup("Service settings") {
                    TextField("Catalog HTTPS URL", text: $catalogURL)
                    TextField("Submission HTTPS URL", text: $reportURL)
                }
                Toggle("Don’t ask for feedback after games", isOn: $disableFeedback)
                HStack {
                    Button("Refresh Catalog") { Task { await compatibility?.refreshCatalog() } }
                    Spacer()
                    if let count = compatibility?.pendingReports.count, count > 0 {
                        Text("\(count) pending")
                        Button("Retry Sending") { Task { await compatibility?.retryPending() } }
                    }
                }
                Text("Only HTTPS endpoints are accepted. Reports are sent only after you choose Submit. A failed submission stays on this Mac until you retry.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .overlay {
            if storage?.isRemoving == true {
                ProgressView("Removing Archway…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: icon) { icon.apply() }
        .navigationTitle("Settings")
        .tint(.archwayAccent)
    }
}

private struct IconChoice: View {
    let icon: AppIcon
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                if let image = icon.image {
                    Image(nsImage: image).resizable().frame(width: 112, height: 112)
                }
                Text(icon.title).font(.callout)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(10)
            .background(isSelected ? Color.archwayAccent.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.archwayAccent : .clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}
