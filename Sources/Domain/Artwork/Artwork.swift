import Foundation

/// A track's cover image, as downloaded.
package struct Artwork: Equatable, Sendable {
    package let url: URL
    package let imageData: Data

    package init(url: URL, imageData: Data) {
        self.url = url
        self.imageData = imageData
    }
}

/// A downloaded cover plus the colours picked from it.
package struct LoadedArtwork: Equatable, Sendable {
    package let artwork: Artwork
    package let palette: AlbumPalette?

    package init(artwork: Artwork, palette: AlbumPalette?) {
        self.artwork = artwork
        self.palette = palette
    }
}

package protocol ArtworkLoader: Sendable {
    /// Nil when the image can't be downloaded or decoded.
    func loadArtwork(from url: URL) async -> LoadedArtwork?
}
