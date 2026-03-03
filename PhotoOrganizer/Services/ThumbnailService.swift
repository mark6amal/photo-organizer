import Foundation
import ImageIO
import AppKit
import CoreImage

actor ThumbnailService {
    static let shared = ThumbnailService()

    // Small thumbnails (800px) — one per URL, no eviction needed
    private var cache: [URL: NSImage] = [:]

    // Large previews (2400px) — bounded FIFO to cap memory
    private var previewCache: [(url: URL, image: NSImage)] = []
    private let maxPreviews = 20

    // Full-resolution cache — NSCache is internally thread-safe
    private let fullResCache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 3
        c.totalCostLimit = 500 * 1024 * 1024 // 500 MB
        return c
    }()

    // MARK: - Thumbnail (grid / carousel)

    func thumbnail(for url: URL, maxPixelSize: Int = 800) async -> NSImage? {
        if let cached = cache[url] { return cached }

        let image = await Task.detached(priority: .utility) {
            Self.decode(url: url, maxPixelSize: maxPixelSize)
        }.value

        if let image { cache[url] = image }
        return image
    }

    // MARK: - Preview (filmstrip large view)

    func preview(for url: URL) async -> NSImage? {
        if let hit = previewCache.first(where: { $0.url == url })?.image { return hit }

        let image = await Task.detached(priority: .userInitiated) {
            Self.decode(url: url, maxPixelSize: 2400)
        }.value

        if let image {
            if previewCache.count >= maxPreviews { previewCache.removeFirst() }
            previewCache.append((url, image))
        }
        return image
    }

    // MARK: - Full resolution (filmstrip sharp display)

    func fullResolution(for url: URL) async -> NSImage? {
        if let cached = fullResCache.object(forKey: url as NSURL) { return cached }

        let image = await Task.detached(priority: .userInitiated) {
            Self.decodeFullResolution(url: url)
        }.value

        if let image {
            let cost = Int(image.size.width * image.size.height) * 4
            fullResCache.setObject(image, forKey: url as NSURL, cost: cost)
            return image
        }
        return await preview(for: url)
    }

    // MARK: - Decode (runs off-actor in Task.detached)

    private static func decode(url: URL, maxPixelSize: Int) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: false,
        ]

        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Full resolution decode with orientation correction

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private static func decodeFullResolution(url: URL) -> NSImage? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        return applyOrientation(cgImage: cgImage, source: source)
    }

    private static func applyOrientation(cgImage: CGImage, source: CGImageSource) -> NSImage? {
        guard
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let orientationRaw = props[kCGImagePropertyOrientation] as? UInt32,
            let orientation = CGImagePropertyOrientation(rawValue: orientationRaw),
            orientation != .up
        else {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }

        let ciImage = CIImage(cgImage: cgImage).oriented(orientation)
        guard let rotated = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        return NSImage(cgImage: rotated, size: NSSize(width: rotated.width, height: rotated.height))
    }
}
