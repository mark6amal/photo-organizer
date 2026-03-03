import Foundation
import AppKit

struct HistogramData: Sendable {
    let red: [Float]    // 64 bins, normalized 0…1
    let green: [Float]
    let blue: [Float]
    let luma: [Float]
}

actor HistogramService {
    static let shared = HistogramService()

    private var cache: [URL: HistogramData] = [:]

    func histogram(for url: URL) async -> HistogramData? {
        if let cached = cache[url] { return cached }
        let data = await Task.detached(priority: .utility) {
            Self.compute(url: url)
        }.value
        if let data { cache[url] = data }
        return data
    }

    func clearCache() { cache.removeAll() }

    // MARK: - Computation

    private static func compute(url: URL) -> HistogramData? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 400,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
        else { return nil }

        let w = cg.width, h = cg.height
        let bpr = w * 4
        var pixels = [UInt8](repeating: 0, count: h * bpr)

        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Count into 256-bin histograms (ARGB layout: A=i, R=i+1, G=i+2, B=i+3)
        var rBins = [Int](repeating: 0, count: 256)
        var gBins = [Int](repeating: 0, count: 256)
        var bBins = [Int](repeating: 0, count: 256)
        var lBins = [Int](repeating: 0, count: 256)

        var i = 0
        while i < pixels.count {
            let r = Int(pixels[i &+ 1])
            let g = Int(pixels[i &+ 2])
            let b = Int(pixels[i &+ 3])
            rBins[r] += 1
            gBins[g] += 1
            bBins[b] += 1
            let luma = (r * 299 + g * 587 + b * 114) / 1000
            lBins[luma] += 1
            i += 4
        }

        return HistogramData(
            red: downsample(rBins),
            green: downsample(gBins),
            blue: downsample(bBins),
            luma: downsample(lBins)
        )
    }

    private static func downsample(_ bins: [Int], targetBins: Int = 64) -> [Float] {
        let stride = bins.count / targetBins
        var out = [Float](repeating: 0, count: targetBins)
        for i in 0..<targetBins {
            let sum = bins[(i * stride)..<((i + 1) * stride)].reduce(0, +)
            out[i] = Float(sum)
        }
        let peak = out.max() ?? 1
        return peak > 0 ? out.map { $0 / peak } : out
    }
}
