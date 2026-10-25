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
    @AppStorage(AppIcon.defaultsKey) private var icon = AppIcon.glow

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
            Section("App Icon") {
                HStack(spacing: 20) {
                    ForEach(AppIcon.allCases) { option in
                        IconChoice(icon: option, isSelected: option == icon) { icon = option }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
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
