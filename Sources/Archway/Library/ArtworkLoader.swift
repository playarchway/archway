import AppKit

/// Loads and keeps game artwork for tiles, backdrops, and pages. Newer games keep their header under
/// a hashed path, so a failed load asks the store for the real URL.
@MainActor
final class ArtworkLoader {
    static let shared = ArtworkLoader()

    private enum Kind: Hashable { case header, backdrop }
    private struct Key: Hashable {
        let kind: Kind
        let id: Int
    }

    /// The system evicts these under memory pressure; URLSession's cache still has the downloads.
    private let headers = NSCache<NSNumber, NSImage>()
    private let backdrops = NSCache<NSNumber, NSImage>()
    /// Loads in flight, so views that ask for the same artwork at once share one download.
    private var loading: [Key: Task<NSImage?, Never>] = [:]

    private init() {
        headers.countLimit = 300
        // Full-size store backgrounds take several megabytes each once drawn.
        backdrops.countLimit = 20
    }

    func header(for game: LibraryGame) async -> NSImage? {
        guard !game.isLocal else { return nil }
        return await image(Key(kind: .header, id: game.id)) {
            if let image = await Self.load(game.headerURL) { return image }
            guard let url = try? await SteamStoreClient.shared.details(for: game.id).headerImage else { return nil }
            return await Self.load(url)
        }
    }

    /// The wide store background for a game's page, falling back to its header.
    func backdrop(for game: LibraryGame) async -> NSImage? {
        await image(Key(kind: .backdrop, id: game.id)) {
            if !game.isLocal, let url = try? await SteamStoreClient.shared.details(for: game.id).backgroundRaw,
               let image = await Self.load(url) { return image }
            return await self.header(for: game)
        }
    }

    func cachedHeader(for game: LibraryGame) -> NSImage? { headers.object(forKey: game.id as NSNumber) }
    func cachedBackdrop(for game: LibraryGame) -> NSImage? { backdrops.object(forKey: game.id as NSNumber) }

    private func cache(for kind: Kind) -> NSCache<NSNumber, NSImage> { kind == .header ? headers : backdrops }

    private func image(_ key: Key, load: @escaping @MainActor () async -> NSImage?) async -> NSImage? {
        if let cached = cache(for: key.kind).object(forKey: key.id as NSNumber) { return cached }
        if let running = loading[key] { return await running.value }
        let task = Task { await load() }
        loading[key] = task
        let image = await task.value
        loading[key] = nil
        if let image { cache(for: key.kind).setObject(image, forKey: key.id as NSNumber) }
        return image
    }

    /// Decodes here, off the main thread; an `NSImage(data:)` would decode on its first draw, in the middle of a scroll.
    nonisolated private static func load(_ url: URL) async -> NSImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
