import Foundation
import Vision

actor VisionService {
    static let shared = VisionService()

    private var printCache: [URL: VNFeaturePrintObservation] = [:]

    // MARK: - Feature Print

    func featurePrint(for url: URL) async -> VNFeaturePrintObservation? {
        if let cached = printCache[url] { return cached }
        let obs = await Task.detached(priority: .utility) {
            Self.computePrint(url: url)
        }.value
        if let obs { printCache[url] = obs }
        return obs
    }

    private static func computePrint(url: URL) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(url: url, options: [:])
        try? handler.perform([request])
        return request.results?.first
    }

    func clearCache() { printCache.removeAll() }

    // MARK: - Clustering (Union-Find)

    func cluster(photos: [Photo], distanceThreshold: Float = 0.35) async -> [[Photo]] {
        guard photos.count > 1 else { return [photos] }

        // Gather feature prints
        var observations: [Int: VNFeaturePrintObservation] = [:]
        for (i, photo) in photos.enumerated() {
            if let obs = await featurePrint(for: photo.thumbnailSourceURL) {
                observations[i] = obs
            }
        }

        // Union-Find
        var parent = Array(0..<photos.count)

        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }

        func unite(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        let keys = observations.keys.sorted()
        for i in 0..<keys.count {
            for j in (i + 1)..<keys.count {
                let a = keys[i], b = keys[j]
                guard let obsA = observations[a], let obsB = observations[b] else { continue }
                var dist: Float = 0
                if (try? obsA.computeDistance(&dist, to: obsB)) != nil, dist < distanceThreshold {
                    unite(a, b)
                }
            }
        }

        // Collect clusters
        var clusters: [Int: [Int]] = [:]
        for i in 0..<photos.count {
            clusters[find(i), default: []].append(i)
        }

        return clusters
            .sorted { $0.value.min()! < $1.value.min()! }
            .map { $0.value.sorted().map { photos[$0] } }
    }
}
