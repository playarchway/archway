import SwiftUI

struct PlayButton: View {
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
struct RunningIndicator: View {
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

struct StatusPill: View {
    let compatibility: LibraryGame.Compatibility

    var body: some View {
        Label(compatibility.headline, systemImage: compatibility.symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(compatibility.color == .secondary ? .primary : compatibility.color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(compatibility.color.opacity(0.18), in: Capsule())
    }
}

/// The game's color, slowly breathing while its artwork loads.
struct HeroPlaceholder: View {
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
struct LaunchGlow: View {
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
