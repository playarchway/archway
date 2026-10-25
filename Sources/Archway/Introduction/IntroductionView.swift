import SwiftUI

/// A short introduction on first start. Setup already runs underneath, and the third page shows it live.
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
            AmbientBackground(game: nil)
            RadialGradient(colors: [Color.archwayAccent.opacity(0.18), .clear], center: .init(x: 0.5, y: 0.32),
                           startRadius: 10, endRadius: 520)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ArchMark(page: page, setupFraction: setup.fractionDone)
                    .frame(width: page == .howItWorks ? 130 : 220, height: page == .howItWorks ? 130 : 220)
                    .padding(.bottom, 28)
                    .animation(.spring(response: 0.7, dampingFraction: 0.8), value: page)

                ZStack {
                    pageContent
                        .id(page)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .offset(x: isMovingForward ? 60 : -60).combined(with: .opacity),
                            removal: .offset(x: isMovingForward ? -60 : 60).combined(with: .opacity)))
                }
                .frame(maxWidth: 640, minHeight: 260, alignment: .top)

                controls.padding(.top, 20)
            }
            .padding(48)
        }
        .overlay(alignment: .topTrailing) {
            if page != Page.allCases.last {
                Button("Skip") { onFinish(false) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.top, 22)
                    .padding(.trailing, 28)
            }
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
                PageText(title: String(localized: "How Archway Works"), message: nil)
                HStack(alignment: .top, spacing: 14) {
                    FeatureCard(symbol: "square.stack.3d.up.fill", title: String(localized: "Windows Layer"),
                                message: String(localized: "Wine answers the questions a game asks Windows, in macOS terms."),
                                delay: 0.05)
                    FeatureCard(symbol: "sparkles", title: String(localized: "Graphics on Metal"),
                                message: String(localized: "Apple’s D3DMetal turns DirectX into Metal for your Mac’s graphics chip."),
                                delay: 0.15)
                    FeatureCard(symbol: "gamecontroller.fill", title: String(localized: "Your Steam Library"),
                                message: String(localized: "Your games come from Steam, which runs in its own Windows environment."),
                                delay: 0.25)
                }
            }
        case .setup:
            VStack(spacing: 22) {
                PageText(title: setup.isReady ? String(localized: "All Set") : String(localized: "Already Underway"),
                         message: setup.isReady
                         ? String(localized: "Windows support is ready.")
                         : String(localized: "Archway is setting up Windows support while you read this. It takes a few minutes, and you can use your library meanwhile."))
                SetupChecklist()
                    .padding(18)
                    .frame(width: 300, alignment: .leading)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 540)
            }
        }
        .multilineTextAlignment(.center)
    }
}

private struct FeatureCard: View {
    let symbol: String
    let title: String
    let message: String
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.archwayAccent)
                .symbolEffect(.bounce, value: isVisible)
                .frame(height: 30, alignment: .leading)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 200, height: 170, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08))
        }
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible || reduceMotion ? 0 : 16)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(delay)) { isVisible = true }
        }
    }
}

/// Archway's arch as a line of light. It draws itself on the first page, waits smaller on the explanation,
/// fills with the setup's progress on the setup page, and glows fully at the end.
private struct ArchMark: View {
    let page: IntroductionView.Page
    let setupFraction: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var breathes = false

    private var trim: CGFloat {
        switch page {
        case .welcome, .howItWorks: drawn
        case .setup: max(0.04, setupFraction)
        case .steam: 1
        }
    }

    var body: some View {
        ZStack {
            // The floor glow under the arch, as in the app icon.
            GeometryReader { proxy in
                Ellipse()
                    .fill(RadialGradient(colors: [Color.archwayAccent.opacity(0.55), .clear], center: .center,
                                         startRadius: 0, endRadius: proxy.size.width / 2))
                    .frame(width: proxy.size.width * 1.1, height: proxy.size.width * 0.21)
                    .position(x: proxy.size.width / 2, y: proxy.size.height - 12)
            }
                .opacity(Double(trim) * (breathes ? 1 : 0.7))
                .blur(radius: 6)

            // Faint guide of the full arch, so the setup page reads as progress.
            ArchShape()
                .stroke(.white.opacity(page == .setup ? 0.1 : 0), style: .init(lineWidth: 18, lineCap: .round))

            ArchShape()
                .trim(from: 0, to: trim)
                .stroke(Color.archwayAccent, style: .init(lineWidth: 18, lineCap: .round))
                .blur(radius: breathes ? 22 : 16)
                .opacity(0.9)
            ArchShape()
                .trim(from: 0, to: trim)
                .stroke(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.62), .archwayAccent],
                                       startPoint: .top, endPoint: .bottom),
                        style: .init(lineWidth: 14, lineCap: .round))
        }
        .animation(.easeInOut(duration: 0.6), value: setupFraction)
        .onAppear {
            guard !reduceMotion else { drawn = 1; return }
            withAnimation(.easeInOut(duration: 1.6).delay(0.2)) { drawn = 1 }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true).delay(1.8)) { breathes = true }
        }
    }
}

/// The arch from the app icon: two legs and a half circle, drawn from the left foot to the right one.
private struct ArchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width * 0.78
        let radius = width / 2
        let left = rect.midX - radius
        let right = rect.midX + radius
        let top = rect.minY + radius + 8
        let bottom = rect.maxY - 12
        var path = Path()
        path.move(to: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left, y: top))
        path.addArc(center: CGPoint(x: rect.midX, y: top), radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: right, y: bottom))
        return path
    }
}
