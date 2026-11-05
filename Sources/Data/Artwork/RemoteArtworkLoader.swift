import AppDomain
import CoreGraphics
import Foundation
import ImageIO

/// Downloads covers and picks their colours from a small thumbnail.
package struct RemoteArtworkLoader: ArtworkLoader {
    private let transport: HTTPTransport

    package init(transport: HTTPTransport) {
        self.transport = transport
    }

    package func loadArtwork(from url: URL) async -> LoadedArtwork? {
        guard let (data, _) = try? await transport.send(URLRequest(url: url)),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let palette = Self.thumbnailPixels(of: image).flatMap(AlbumPalette.extract(fromRGBA:))
        return LoadedArtwork(artwork: Artwork(url: url, imageData: data), palette: palette)
    }

    /// The image shrunk to `AlbumPalette.sampleSide` squared, as RGBA bytes.
    private static func thumbnailPixels(of image: CGImage) -> [UInt8]? {
        let side = AlbumPalette.sampleSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drew ? pixels : nil
    }
}
