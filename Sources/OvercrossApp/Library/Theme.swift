import SwiftUI

extension Color {
    /// Overcross' accent: a warm amber that stays clear of the green and red compatibility states.
    static let overcrossAccent = Color(red: 1.0, green: 0.72, blue: 0.26)
}

extension Animation {
    /// Shared spring for opening and closing a game, so cover and page move as one.
    static let overcrossHero = Animation.spring(response: 0.48, dampingFraction: 0.86)
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

    @State private var layers: [Layer] = []

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

            if game == nil {
                RadialGradient(colors: [Color.overcrossAccent.opacity(0.16), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 900)
                    .transition(.opacity)
            }

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
        guard let game else {
            withAnimation(.easeInOut(duration: 0.6)) {
                for index in layers.indices { layers[index].isVisible = false }
            }
            return
        }
        guard let image = await ArtworkLoader.shared.header(for: game), !Task.isCancelled else { return }

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

/// Loads and keeps game header artwork for the backdrop. Newer games keep it under a hashed path,
/// so a failed load asks the store for the real URL.
@MainActor
final class ArtworkLoader {
    static let shared = ArtworkLoader()
    private var images: [Int: NSImage] = [:]

    func header(for game: LibraryGame) async -> NSImage? {
        if let cached = images[game.id] { return cached }
        guard !game.isLocal else { return nil }
        var image = await load(game.headerURL)
        if image == nil, let storeURL = try? await SteamStoreClient.shared.details(for: game.id).headerImage {
            image = await load(storeURL)
        }
        if let image { images[game.id] = image }
        return image
    }

    private func load(_ url: URL) async -> NSImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return NSImage(data: data)
    }
}
