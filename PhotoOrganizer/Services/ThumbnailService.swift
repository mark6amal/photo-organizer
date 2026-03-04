import Foundation
import ImageIO
import AppKit
import CoreImage

extension NSImage: @retroactive @unchecked Sendable {}

actor ThumbnailService {
    static let shared = ThumbnailService()

    private struct RasterKey: Hashable {
        let url: URL
        let pixelSize: Int
    }

    private struct CacheEntry {
        let image: NSImage
        let cost: Int
        var stamp: UInt64
    }

    private var stamp: UInt64 = 0

    // Small raster tiers (grid / carousel)
    private var thumbnailCache: [RasterKey: CacheEntry] = [:]
    private var thumbnailCost = 0
    private let thumbnailCostLimit = 160 * 1024 * 1024
    private let thumbnailCountLimit = 240

    // Large preview tiers (fast filmstrip display)
    private var previewCache: [RasterKey: CacheEntry] = [:]
    private var previewCost = 0
    private let previewCostLimit = 220 * 1024 * 1024
    private let previewCountLimit = 8

    // Full-resolution cache (current image only or very small working set)
    private var fullResCache: [URL: CacheEntry] = [:]
    private var fullResCost = 0
    private let fullResCostLimit = 260 * 1024 * 1024
    private let fullResCountLimit = 1

    // MARK: - Thumbnail (grid / carousel)

    func thumbnail(for url: URL, maxPixelSize: Int = 800) async -> NSImage? {
        let key = RasterKey(url: url, pixelSize: maxPixelSize)
        if let cached = cachedImage(for: key, in: &thumbnailCache) {
            return cached
        }
        let image = await Task.detached(priority: .utility) {
            Self.decode(url: url, maxPixelSize: maxPixelSize)
        }.value

        if let image {
            insert(
                image,
                for: key,
                into: &thumbnailCache,
                totalCost: &thumbnailCost,
                costLimit: thumbnailCostLimit,
                countLimit: thumbnailCountLimit
            )
        }
        return image
    }

    // MARK: - Preview (filmstrip large view)

    func preview(for url: URL, maxPixelSize: Int = 2200) async -> NSImage? {
        let key = RasterKey(url: url, pixelSize: maxPixelSize)
        if let cached = cachedImage(for: key, in: &previewCache) {
            return cached
        }
        let image = await Task.detached(priority: .userInitiated) {
            Self.decode(url: url, maxPixelSize: maxPixelSize)
        }.value

        if let image {
            insert(
                image,
                for: key,
                into: &previewCache,
                totalCost: &previewCost,
                costLimit: previewCostLimit,
                countLimit: previewCountLimit
            )
        }
        return image
    }

    // MARK: - Full resolution (filmstrip sharp display)

    func fullResolution(for url: URL) async -> NSImage? {
        if let cached = cachedImage(for: url, in: &fullResCache) {
            return cached
        }
        let image = await Task.detached(priority: .userInitiated) {
            Self.decodeFullResolution(url: url)
        }.value

        if let image {
            insert(
                image,
                for: url,
                into: &fullResCache,
                totalCost: &fullResCost,
                costLimit: fullResCostLimit,
                countLimit: fullResCountLimit
            )
            return image
        }
        return await preview(for: url)
    }

    // MARK: - Cache trimming

    func retainWindow(currentURL: URL?, nearbyURLs: [URL]) {
        let nearby = Set(nearbyURLs)

        trim(cache: &thumbnailCache, totalCost: &thumbnailCost) { key in
            nearby.contains(key.url)
        }
        trim(cache: &previewCache, totalCost: &previewCost) { key in
            nearby.contains(key.url)
        }
        trim(cache: &fullResCache, totalCost: &fullResCost) { key in
            guard let currentURL else { return false }
            return key == currentURL
        }
    }

    func clearAll() {
        thumbnailCache.removeAll()
        previewCache.removeAll()
        fullResCache.removeAll()
        thumbnailCost = 0
        previewCost = 0
        fullResCost = 0
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

    // MARK: - LRU helpers

    private func cachedImage<K: Hashable>(for key: K, in cache: inout [K: CacheEntry]) -> NSImage? {
        guard var entry = cache[key] else { return nil }
        entry.stamp = nextStamp()
        cache[key] = entry
        return entry.image
    }

    private func insert<K: Hashable>(
        _ image: NSImage,
        for key: K,
        into cache: inout [K: CacheEntry],
        totalCost: inout Int,
        costLimit: Int,
        countLimit: Int
    ) {
        if let existing = cache.removeValue(forKey: key) {
            totalCost -= existing.cost
        }

        let entry = CacheEntry(image: image, cost: imageCost(image), stamp: nextStamp())
        cache[key] = entry
        totalCost += entry.cost

        while totalCost > costLimit || cache.count > countLimit {
            guard let victimKey = cache.min(by: { $0.value.stamp < $1.value.stamp })?.key,
                  let victim = cache.removeValue(forKey: victimKey)
            else { break }
            totalCost -= victim.cost
        }
    }

    private func trim<K: Hashable>(
        cache: inout [K: CacheEntry],
        totalCost: inout Int,
        keeping shouldKeep: (K) -> Bool
    ) {
        let staleKeys = cache.keys.filter { !shouldKeep($0) }
        for key in staleKeys {
            if let removed = cache.removeValue(forKey: key) {
                totalCost -= removed.cost
            }
        }
    }

    private func nextStamp() -> UInt64 {
        stamp += 1
        return stamp
    }

    private func imageCost(_ image: NSImage) -> Int {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return max(1, cgImage.width * cgImage.height * 4)
        }
        return max(1, Int(image.size.width * image.size.height) * 4)
    }
}
