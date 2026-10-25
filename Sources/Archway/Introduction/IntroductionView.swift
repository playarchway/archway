import AppKit
import SwiftUI

/// A short introduction on first start. Each page is a scene in the app icon's glowing glass;
/// setup already runs underneath, and the third page shows it live.
struct IntroductionView: View {
    enum Page: Int, CaseIterable {
        case welcome, howItWorks, setup, steam
    }

    let hasSteamAccount: Bool
    /// Called with `true` when the user wants to link Steam right away.
    let onFinish: (_ linkSteam: Bool) -> Void

    @Environment(SetupModel.self) private var setup
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Page
    @State private var isMovingForward = true

    init(hasSteamAccount: Bool, startPage: Page = .welcome, onFinish: @escaping (_ linkSteam: Bool) -> Void) {
        self.hasSteamAccount = hasSteamAccount
        self.onFinish = onFinish
        _page = State(initialValue: startPage)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Scenes cross-fade; each keeps its own slow camera move.
            ZStack {
                scene.id(page).transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.9), value: page)

            // Darken the lower part so the text reads on the floor's reflection.
            LinearGradient(stops: [.init(color: .clear, location: 0.42),
                                   .init(color: .black.opacity(0.75), location: 0.66),
                                   .init(color: .black, location: 0.92)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 22) {
                Spacer(minLength: 0)
                ZStack {
                    pageContent
                        .id(page)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .offset(x: isMovingForward ? 60 : -60).combined(with: .opacity),
                            removal: .offset(x: isMovingForward ? -60 : 60).combined(with: .opacity)))
                }
                .frame(maxWidth: 820)
                controls
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 40)
        }
        .overlay(alignment: .topTrailing) {
            if page != Page.allCases.last {
                Button("Skip") { onFinish(false) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 22)
                    .padding(.trailing, 28)
            }
        }
    }

    // MARK: Scenes

    @ViewBuilder private var scene: some View {
        switch page {
        case .welcome:
            IntroScene(image: "intro-welcome", revealsFromDark: true)
        case .howItWorks:
            IntroScene(image: "intro-arch")
                .opacity(0.45)
                .blur(radius: 10)
        case .setup:
            IntroScene(image: "intro-arch") {
                LitArch(fraction: setup.fractionDone)
            }
        case .steam:
            IntroScene(image: "intro-steam", floats: true)
        }
    }

    // MARK: Pages

    @ViewBuilder private var pageContent: some View {
        switch page {
        case .welcome:
            PageText(title: String(localized: "Welcome to Archway"),
                     message: String(localized: "Play your Windows games on this Mac. Archway sets up everything they need and keeps it out of your way."))
        case .howItWorks:
            VStack(spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    FeatureCard(image: "intro-card-wine", title: String(localized: "Windows Layer"),
                                message: String(localized: "Wine answers the questions a game asks Windows, in macOS terms."),
                                delay: 0.1)
                    FeatureCard(image: "intro-card-metal", title: String(localized: "Graphics on Metal"),
                                message: String(localized: "Apple’s D3DMetal turns DirectX into Metal for your Mac’s graphics chip."),
                                delay: 0.22)
                    FeatureCard(image: "intro-card-library", title: String(localized: "Your Steam Library"),
                                message: String(localized: "Your games come from Steam, which runs in its own Windows environment."),
                                delay: 0.34)
                }
                PageText(title: String(localized: "How Archway Works"), message: nil)
            }
        case .setup:
            VStack(spacing: 18) {
                PageText(title: setup.isReady ? String(localized: "All Set") : String(localized: "Already Underway"),
                         message: setup.isReady
                         ? String(localized: "Windows support is ready.")
                         : String(localized: "Archway is setting up Windows support while you read this. It takes a few minutes, and you can use your library meanwhile."))
                SetupChecklist(axis: .horizontal)
            }
        case .steam:
            PageText(title: hasSteamAccount ? String(localized: "Ready to Play") : String(localized: "Bring Your Games"),
                     message: hasSteamAccount
                     ? String(localized: "Your Steam library is linked. Pick a game and press Play.")
                     : String(localized: "Link your Steam account to see the games you own. You sign in on Steam’s own page; Archway never sees your password."))
        }
    }

    // MARK: Controls

    /// Back, the page dots, and the next step, with the dots fixed in the middle.
    private var controls: some View {
        HStack(spacing: 24) {
            Button("Back") { go(to: page.rawValue - 1) }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .opacity(page == .welcome ? 0 : 1)
                .disabled(page == .welcome)
                .frame(width: 220, alignment: .trailing)

            HStack(spacing: 8) {
                ForEach(Page.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == page ? Color.archwayAccent : .white.opacity(0.25))
                        .frame(width: item == page ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: page)

            nextButtons.frame(width: 220, alignment: .leading)
        }
    }

    @ViewBuilder private var nextButtons: some View {
        HStack(spacing: 10) {
            if page == .steam && !hasSteamAccount {
                Button("Later") { onFinish(false) }
                    .controlSize(.large)
                Button("Link Steam…") { onFinish(true) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(page == .steam ? String(localized: "Start Playing") : String(localized: "Continue")) {
                    if page == .steam { onFinish(false) } else { go(to: page.rawValue + 1) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func go(to index: Int) {
        guard let next = Page(rawValue: index) else { return }
        isMovingForward = next.rawValue > page.rawValue
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { page = next }
    }
}

// MARK: - Scene

/// One of the introduction's artworks (1536 × 1024), filling the window with the arch in its upper part.
/// It drifts like a slow camera move and follows the pointer a little. `overlay` draws in image coordinates.
private struct IntroScene<Overlay: View>: View {
    static var size: CGSize { CGSize(width: 1536, height: 1024) }

    let image: String
    var revealsFromDark = false
    var floats = false
    @ViewBuilder var overlay: () -> Overlay

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var drifts = false
    @State private var pointer: CGSize = .zero

    init(image: String, revealsFromDark: Bool = false, floats: Bool = false,
         @ViewBuilder overlay: @escaping () -> Overlay = { EmptyView() }) {
        self.image = image
        self.revealsFromDark = revealsFromDark
        self.floats = floats
        self.overlay = overlay
    }

    var body: some View {
        GeometryReader { proxy in
            // The arch spans y 145…740 in every artwork. Fit it into the upper 62 % of the window, from 6 % down,
            // and fill the width; the artworks fade to black at their edges.
            let scale = max(proxy.size.width / Self.size.width, 0.62 * proxy.size.height / 595)
            let lift = 0.06 * proxy.size.height - proxy.size.height / 2 - (145 - Self.size.height / 2) * scale
            ZStack {
                if let artwork = IntroArtwork.image(image) {
                    Image(nsImage: artwork).resizable()
                }
                overlay()
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .scaleEffect(scale * (drifts ? 1.05 : 1) * (hasAppeared || !revealsFromDark ? 1 : 1.12))
            .offset(x: pointer.width * -14, y: pointer.height * -10 + (floats && drifts ? -8 : 0))
            .offset(y: lift)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .brightness(revealsFromDark && !hasAppeared ? -1 : 0)
            .clipped()
            .onContinuousHover { phase in
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.6)) {
                    if case .active(let location) = phase {
                        pointer = CGSize(width: location.x / proxy.size.width - 0.5, height: location.y / proxy.size.height - 0.5)
                    } else {
                        pointer = .zero
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { hasAppeared = true; return }
            withAnimation(.easeOut(duration: revealsFromDark ? 2.4 : 0.01)) { hasAppeared = true }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { drifts = true }
        }
    }
}

private enum IntroArtwork {
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor static func image(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        let image = Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Introduction")
            .flatMap(NSImage.init(contentsOf:))
        cache[name] = image
        return image
    }
}

/// The arch artwork, unlit, with light running along the glass from the left foot to the right one
/// as setup moves on. Drawn in the artwork's coordinates.
private struct LitArch: View {
    let fraction: Double

    var body: some View {
        ZStack {
            // The dark arch: the same glass with its light switched off.
            if let artwork = IntroArtwork.image("intro-arch") {
                Image(nsImage: artwork).resizable()
                    .saturation(0)
                    .brightness(-0.32)
                    .contrast(1.1)
                    .mask(alignment: .center) {
                        ZStack {
                            // The glow on the floor brightens with the whole setup.
                            Rectangle().opacity(0.85 * (1 - fraction))
                            ArchCenterline()
                                .trim(from: max(0.001, fraction), to: 1)
                                .stroke(style: .init(lineWidth: 150, lineCap: .butt))
                                .blur(radius: 14)
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 1.2), value: fraction)
    }
}

/// The centre line of the glass arch in the 1536 × 1024 artwork, from the left foot over the top to the right foot.
private struct ArchCenterline: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 1536, sy = rect.height / 1024
        let center = CGPoint(x: 763.5 * sx, y: 407 * sy)
        let radius = 202.5 * sx
        var path = Path()
        path.move(to: CGPoint(x: center.x - radius, y: 760 * sy))
        path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        path.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: center.x + radius, y: 760 * sy))
        return path
    }
}

// MARK: - Text and cards

private struct PageText: View {
    let title: String
    let message: String?

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 40, weight: .bold))
            if let message {
                Text(message)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: 560)
            }
        }
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.6), radius: 12)
    }
}

private struct FeatureCard: View {
    let image: String
    let title: String
    let message: String
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @State private var tilt: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let artwork = IntroArtwork.image(image) {
                    Image(nsImage: artwork).resizable().scaledToFill()
                }
            }
            .frame(width: 236, height: 150)
            .scaleEffect(isVisible ? 1.06 : 1.2)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 236, height: 108, alignment: .topLeading)
        }
        .background(.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.1))
        }
        .rotation3DEffect(.degrees(Double(tilt.height) * -6), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(Double(tilt.width) * 8), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible || reduceMotion ? 0 : 24)
        .onContinuousHover { phase in
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                if case .active(let location) = phase {
                    tilt = CGSize(width: location.x / 236 - 0.5, height: location.y / 258 - 0.5)
                } else {
                    tilt = .zero
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(delay)) { isVisible = true }
        }
    }
}
