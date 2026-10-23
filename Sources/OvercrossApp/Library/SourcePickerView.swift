import SwiftUI

/// The start page while no game source is linked: game platforms as tiles, plus adding a local .exe.
struct SourcePickerView: View {
    let isLinking: Bool
    let linkError: String?
    let onLinkSteam: () -> Void
    let onAddGame: () -> Void

    @State private var hasAppeared = false

    private let sources: [GameSource] = [
        GameSource(name: "Steam", colors: [Color(red: 0.09, green: 0.16, blue: 0.24), Color(red: 0.16, green: 0.33, blue: 0.47)],
                   isAvailable: true),
        GameSource(name: "GOG", colors: [Color(red: 0.36, green: 0.13, blue: 0.4), Color(red: 0.55, green: 0.22, blue: 0.58)],
                   isAvailable: false),
        GameSource(name: "Epic Games", colors: [Color(white: 0.12), Color(white: 0.24)], isAvailable: false),
        GameSource(name: "itch.io", colors: [Color(red: 0.62, green: 0.2, blue: 0.22), Color(red: 0.98, green: 0.36, blue: 0.36)],
                   isAvailable: false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Deine Bibliothek ist noch leer.", systemImage: "square.stack")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Spiele hinzufügen")
                    .font(.system(size: 40, weight: .bold))
            }

            HStack(spacing: 18) {
                ForEach(Array(sources.enumerated()), id: \.element.name) { index, source in
                    SourceTile(source: source, isBusy: isLinking && source.isAvailable, action: onLinkSteam)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 18)
                        .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(Double(index) * 0.06),
                                   value: hasAppeared)
                }
            }

            if let linkError {
                Label(linkError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }

            HStack(spacing: 16) {
                Image(systemName: "plus.square.dashed")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Color.overcrossAccent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Windows-Spiel hinzufügen").font(.headline)
                    Text("Eine .exe von deinem Mac").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Datei auswählen …", action: onAddGame)
                    .controlSize(.large)
            }
            .padding(20)
            .frame(maxWidth: 4 * 240 + 3 * 18)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(hasAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.3), value: hasAppeared)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { hasAppeared = true }
        .animation(.snappy, value: linkError)
    }
}

private struct GameSource {
    let name: String
    let colors: [Color]
    let isAvailable: Bool
}

private struct SourceTile: View {
    let source: GameSource
    let isBusy: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: source.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(source.name)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 6) {
                    if isBusy { ProgressView().controlSize(.mini) }
                    Text(source.isAvailable ? "Verknüpfen" : "Bald verfügbar")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(source.isAvailable ? .black : .white.opacity(0.8))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(source.isAvailable ? Color.overcrossAccent : .white.opacity(0.15), in: Capsule())
                .padding(12)
            }
            .frame(width: 240, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.overcrossAccent.opacity(isHovered && source.isAvailable ? 0.9 : 0), lineWidth: 2)
            }
            .saturation(source.isAvailable ? 1 : 0.35)
            .opacity(source.isAvailable ? 1 : 0.6)
            .scaleEffect(isHovered && source.isAvailable ? 1.04 : 1)
            .shadow(color: .black.opacity(isHovered && source.isAvailable ? 0.5 : 0.25), radius: isHovered ? 18 : 8, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(!source.isAvailable || isBusy)
        .onHover { hovering in withAnimation(.snappy(duration: 0.2)) { isHovered = hovering } }
    }
}
