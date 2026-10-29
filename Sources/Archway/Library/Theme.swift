import CoreImage
import SwiftUI

extension Color {
    /// Archway's accent: a warm amber that stays clear of the green and red compatibility states.
    static let archwayAccent = Color(red: 1.0, green: 0.72, blue: 0.26)
}

extension Animation {
    /// Shared spring for opening and closing a game, so cover and page move as one.
    static let archwayHero = Animation.spring(response: 0.48, dampingFraction: 0.86)
}

/// The backdrop: Archway's amber arch behind the library, the open game's artwork behind its page, heavily blurred.
/// A new image loads first and then fades in over the previous one, so the colors blend directly instead of dipping
/// to black. Images are blurred once when they arrive, not on every frame, so scrolling stays smooth.
struct AmbientBackground: View {
    let game: LibraryGame?

    private struct Layer: Identifiable {
        let id = UUID()
        let image: NSImage
        var isVisible = false
    }

    private static let defaultBackdrop = Bundle.archway.url(forResource: "DefaultBackdrop", withExtension: "jpg")
        .flatMap(NSImage.init(contentsOf:)).flatMap(blurred)

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
            image = await ArtworkLoader.shared.header(for: game).flatMap(Self.blurred)
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

    /// The image shrunk, blurred, and saturated once, as a small bitmap that scales up smoothly. Matches what a live
    /// 80-point blur at 1.3 saturation drew across a window-wide image.
    nonisolated private static func blurred(_ image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width: CGFloat = 320
        let input = CIImage(cgImage: cgImage)
        let small = input.transformed(by: CGAffineTransform(scaleX: width / input.extent.width,
                                                            y: width / input.extent.width))
        let output = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 16)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.3])
            .cropped(to: small.extent)
        guard let result = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: result, size: output.extent.size)
    }
}
