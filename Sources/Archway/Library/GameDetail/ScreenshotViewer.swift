import SwiftUI

/// Screenshots over the dimmed game page: the shot large between round arrows, the others as thumbnails beneath.
/// The arrow keys page, Escape or a click beside the shot closes.
struct ScreenshotViewer: View {
    let screenshots: [SteamStoreDetails.Screenshot]
    @Binding var current: SteamStoreDetails.Screenshot?
    @FocusState private var isFocused: Bool

    private var index: Int { screenshots.firstIndex { $0.id == current?.id } ?? 0 }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.6))
                .background(.ultraThinMaterial)
                .onTapGesture { close() }

            VStack(spacing: 22) {
                HStack(spacing: 24) {
                    arrow(-1, symbol: "chevron.left").disabled(index == 0)
                    shot
                    arrow(1, symbol: "chevron.right").disabled(index >= screenshots.count - 1)
                }
                thumbnails
            }
            .padding(.horizontal, 32)
            .padding(.top, 64)
            .padding(.bottom, 28)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: close) { Image(systemName: "xmark") }
                .buttonStyle(CircleIconButtonStyle(size: 36))
                .help("Close")
                .padding(.top, 18).padding(.trailing, 22)
        }
        .ignoresSafeArea()
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .onAppear { isFocused = true }
    }

    private var shot: some View {
        let screenshot = screenshots[index]
        return ZStack {
            // The thumbnail is already loaded; it holds the place until the full image arrives.
            AsyncImage(url: screenshot.pathThumbnail) { $0.resizable().scaledToFit() } placeholder: { Color.white.opacity(0.04) }
            AsyncImage(url: screenshot.pathFull) { phase in
                if let image = phase.image { image.resizable().scaledToFit().transition(.opacity) }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.55), radius: 40, y: 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(screenshot.id)
        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
    }

    private func arrow(_ direction: Int, symbol: String) -> some View {
        Button { step(direction) } label: { Image(systemName: symbol) }
            .buttonStyle(CircleIconButtonStyle(size: 44))
    }

    private var thumbnails: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(screenshots) { screenshot in
                        let isCurrent = screenshot.id == current?.id
                        Button { withAnimation(.snappy) { current = screenshot } } label: {
                            AsyncImage(url: screenshot.pathThumbnail) { $0.resizable().scaledToFill() } placeholder: {
                                Color.white.opacity(0.06)
                            }
                            .frame(width: 128, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(isCurrent ? Color.archwayAccent : .white.opacity(0.12), lineWidth: isCurrent ? 2 : 1)
                            }
                            .opacity(isCurrent ? 1 : 0.55)
                            .scaleEffect(isCurrent ? 1.04 : 1)
                        }
                        .buttonStyle(.plain)
                        .id(screenshot.id)
                    }
                }
                .padding(.horizontal, 4).padding(.vertical, 6)
            }
            .scrollIndicators(.never)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: CGFloat(screenshots.count) * 138)
            .onChange(of: current?.id, initial: true) { _, id in
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func step(_ direction: Int) {
        let target = index + direction
        guard screenshots.indices.contains(target) else { return }
        withAnimation(.snappy) { current = screenshots[target] }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) { current = nil }
    }
}

/// Set while the screenshot viewer covers the page, so the library hides its toolbar beneath it.
struct ScreenshotViewerPresentedKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}
