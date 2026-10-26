import SwiftUI

extension Color {
    /// Archway's accent: a warm amber that stays clear of the green and red compatibility states.
    static let archwayAccent = Color(red: 1.0, green: 0.72, blue: 0.26)
}

extension Animation {
    /// Shared spring for opening and closing a game, so cover and page move as one.
    static let archwayHero = Animation.spring(response: 0.48, dampingFraction: 0.86)
}

/// The library backdrop: the focused game's artwork, heavily blurred. A new game's artwork loads first and
/// then fades in over the previous one, so the colors blend directly instead of dipping to black.
struct AmbientBackground: View {
    let game: LibraryGame?

    private struct Layer: Identifiable {
        let id = UUID()
        let image: NSImage
        var isVisible = false
    }

    /// Until a game is focused, and without games at all, Archway's own amber arch stands in for the artwork.
    private static let defaultBackdrop = Bundle.module.url(forResource: "DefaultBackdrop", withExtension: "jpg")
        .flatMap(NSImage.init(contentsOf:))

    @State private var layers: [Layer] = defaultBackdrop.map { [Layer(image: $0, isVisible: true)] } ?? []

    var body: some View {
        ZStack {
            Color.black
            // An overlay on a flexible color keeps the oversized artwork from widening the layout.
            Color.clear.overlay {
                ZStack {
                    ForEach(layers) { layer in
                        Image(nsImage: layer.image)
                            .resizable()
                            .scaledToFill()
                            .opacity(layer.isVisible ? 1 : 0)
                    }
                }
                .scaleEffect(1.5)
                .blur(radius: 80)
                .saturation(1.3)
                .opacity(0.55)
            }
            .clipped()

            // Keep the shelves legible: darken towards the bottom and the edges.
            LinearGradient(stops: [.init(color: .black.opacity(0.1), location: 0),
                                   .init(color: .black.opacity(0.55), location: 0.55),
                                   .init(color: .black.opacity(0.9), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .top, startRadius: 200, endRadius: 1400)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task(id: game?.id) { await show(game) }
    }

    private func show(_ game: LibraryGame?) async {
        let image: NSImage?
        if let game {
            image = await ArtworkLoader.shared.header(for: game)
            // Fetch the game page's artwork while the game is only focused, so the page opens with it in place.
            Task { _ = await ArtworkLoader.shared.backdrop(for: game) }
        } else {
            image = Self.defaultBackdrop
        }
        guard let image, !Task.isCancelled, layers.last?.image !== image else { return }

        // The new layer starts transparent on top; everything underneath stays as it is until it covers them.
        layers = Array(layers.suffix(2))
        let layer = Layer(image: image)
        layers.append(layer)
        withAnimation(.easeInOut(duration: 0.8)) {
            if let index = layers.firstIndex(where: { $0.id == layer.id }) { layers[index].isVisible = true }
        }
        try? await Task.sleep(for: .seconds(0.85))
        guard !Task.isCancelled else { return }
        layers.removeAll { $0.id != layer.id }
    }
}
