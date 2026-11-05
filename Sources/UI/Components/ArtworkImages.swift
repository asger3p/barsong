import AppDomain
import AppKit

/// Decodes covers once, however often the views showing them redraw.
@MainActor
enum ArtworkImages {
    private static var cached: (url: URL, image: NSImage)?

    static func image(for artwork: Artwork?) -> NSImage? {
        guard let artwork else { return nil }
        if let cached, cached.url == artwork.url { return cached.image }
        guard let image = NSImage(data: artwork.imageData) else { return nil }
        cached = (artwork.url, image)
        return image
    }
}
