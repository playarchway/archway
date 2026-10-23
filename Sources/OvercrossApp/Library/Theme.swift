import SwiftUI

extension Color {
    /// Overcross' accent: a warm amber that stays clear of the green and red compatibility states.
    static let overcrossAccent = Color(red: 1.0, green: 0.72, blue: 0.26)
}

extension Animation {
    /// Shared spring for opening and closing a game, so cover and page move as one.
    static let overcrossHero = Animation.spring(response: 0.48, dampingFraction: 0.86)
}

/// The library backdrop: the focused game's artwork, heavily blurred, cross-fading as focus moves.
struct AmbientBackground: View {
    let game: LibraryGame?

    var body: some View {
        ZStack {
            Color.black
            // An overlay on a flexible color keeps the oversized artwork from widening the layout.
            Color.clear.overlay {
                if let game {
                    GameCover(game: game, cornerRadius: 0, contentMode: .fill)
                        .scaleEffect(1.5)
                        .blur(radius: 80)
                        .saturation(1.3)
                        .opacity(0.55)
                }
            }
            .clipped()
            .id(game?.id)
            .transition(.opacity)

            if game == nil {
                RadialGradient(colors: [Color.overcrossAccent.opacity(0.16), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 900)
            }

            // Keep the shelves legible: darken towards the bottom and the edges.
            LinearGradient(stops: [.init(color: .black.opacity(0.1), location: 0),
                                   .init(color: .black.opacity(0.55), location: 0.55),
                                   .init(color: .black.opacity(0.9), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .top, startRadius: 200, endRadius: 1400)
        }
        .animation(.easeInOut(duration: 0.9), value: game?.id)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
