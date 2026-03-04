import Foundation
import CoreGraphics
import ImageIO

actor PixelSimilarityService {
    static let shared = PixelSimilarityService()
    static func comparisonCount(for photoCount: Int, mode: AppState.SimilarityMode) -> Int {
        guard photoCount > 1 else { return 0 }

        switch mode {
        case .fastBurst:
            return photoCount - 1
        case .balanced:
            var total = 0
            for index in 0..<photoCount {
                total += min(3, photoCount - index - 1)
            }
            return total
        case .thorough:
            return photoCount * (photoCount - 1) / 2
        }
    }

    private var grayscaleCache: [URL: [Float]] = [:]
    private var sharpnessCache: [URL: Float] = [:]

    // MARK: - Public API

    func cluster(
        photos: [Photo],
        mode: AppState.SimilarityMode = .balanced,
        threshold: Float = 0.06
    ) async -> [[Photo]] {
        guard !photos.isEmpty else { return [] }
        guard photos.count > 1 else { return [photos] }

        var grayscaleMaps: [Int: [Float]] = [:]
        for (index, photo) in photos.enumerated() {
            if let grayscale = await grayscale(for: photo.thumbnailSourceURL) {
                grayscaleMaps[index] = grayscale
            }
        }

        var parent = Array(0..<photos.count)

        func find(_ x: Int) -> Int {
            var node = x
            while parent[node] != node {
                parent[node] = parent[parent[node]]
                node = parent[node]
            }
            return node
        }

        func unite(_ a: Int, _ b: Int) {
            let rootA = find(a)
            let rootB = find(b)
            if rootA != rootB {
                parent[rootA] = rootB
            }
        }

        let keys = grayscaleMaps.keys.sorted()
        let maxNeighborDistance: Int? = switch mode {
        case .fastBurst:
            1
        case .balanced:
            3
        case .thorough:
            nil
        }

        for i in 0..<keys.count {
            let upperBound = if let maxNeighborDistance {
                min(keys.count, i + maxNeighborDistance + 1)
            } else {
                keys.count
            }

            for j in (i + 1)..<upperBound {
                let a = keys[i]
                let b = keys[j]
                guard
                    let grayscaleA = grayscaleMaps[a],
                    let grayscaleB = grayscaleMaps[b]
                else { continue }

                if Self.deltaScore(grayscaleA, grayscaleB) < threshold {
                    unite(a, b)
                }
            }
        }

        var clusters: [Int: [Int]] = [:]
        for index in photos.indices {
            clusters[find(index), default: []].append(index)
        }

        return clusters
            .sorted { ($0.value.min() ?? 0) < ($1.value.min() ?? 0) }
            .map { cluster in
                cluster.value.sorted().map { photos[$0] }
            }
    }

    func sharpness(for url: URL) async -> Float? {
        if let cached = sharpnessCache[url] {
            return cached
        }
        guard let grayscale = await grayscale(for: url) else {
            return nil
        }
        let value = Self.laplacianVariance(grayscale)
        sharpnessCache[url] = value
        return value
    }

    func clearCache() {
        grayscaleCache.removeAll()
        sharpnessCache.removeAll()
    }

    // MARK: - Cache

    private func grayscale(for url: URL) async -> [Float]? {
        if let cached = grayscaleCache[url] {
            return cached
        }
        let result = await Task.detached(priority: .utility) {
            Self.loadGrayscale(url: url)
        }.value
        if let result {
            grayscaleCache[url] = result
        }
        return result
    }

    // MARK: - Image Processing

    private static func loadGrayscale(url: URL) -> [Float]? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceShouldCacheImmediately: false,
        ]

        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return nil
        }

        let width = 64
        let height = 64
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return stride(from: 0, to: pixels.count, by: 4).map { offset in
            let red = Float(pixels[offset + 1])
            let green = Float(pixels[offset + 2])
            let blue = Float(pixels[offset + 3])
            return (0.299 * red + 0.587 * green + 0.114 * blue) / 255.0
        }
    }

    private static func deltaScore(_ a: [Float], _ b: [Float]) -> Float {
        let count = min(a.count, b.count)
        guard count > 0 else { return .greatestFiniteMagnitude }

        var deltas = [Float]()
        deltas.reserveCapacity(count)
        for index in 0..<count {
            deltas.append(abs(a[index] - b[index]))
        }

        let n = Float(count)
        let mean = deltas.reduce(0, +) / n
        let variance = deltas.reduce(into: Float.zero) { partial, delta in
            let normalized = abs(delta - mean)
            partial += normalized * normalized
        } / n

        return sqrt(variance)
    }

    private static func laplacianVariance(_ grayscale: [Float], width: Int = 64) -> Float {
        let height = grayscale.count / width
        guard width > 2, height > 2 else { return 0 }

        var laplacian = [Float](repeating: 0, count: grayscale.count)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                laplacian[index] = 4 * grayscale[index]
                    - grayscale[index - width]
                    - grayscale[index + width]
                    - grayscale[index - 1]
                    - grayscale[index + 1]
            }
        }

        let mean = laplacian.reduce(0, +) / Float(laplacian.count)
        return laplacian.reduce(into: Float.zero) { partial, value in
            let delta = value - mean
            partial += delta * delta
        } / Float(laplacian.count)
    }
}
