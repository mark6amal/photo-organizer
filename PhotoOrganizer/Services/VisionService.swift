import Foundation
import Vision

struct FaceDetectionResult: Sendable {
    let faceCount: Int
    let hasClosedEyes: Bool

    static let none = FaceDetectionResult(faceCount: 0, hasClosedEyes: false)
}

actor VisionService {
    static let shared = VisionService()

    private var printCache: [URL: VNFeaturePrintObservation] = [:]
    private var faceCache: [URL: FaceDetectionResult] = [:]

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

    func clearCache() {
        printCache.removeAll()
        faceCache.removeAll()
    }

    // MARK: - Face Detection

    func detectFaces(for url: URL) async -> FaceDetectionResult {
        if let cached = faceCache[url] { return cached }
        let result = await Task.detached(priority: .utility) {
            Self.performFaceDetection(url: url)
        }.value
        faceCache[url] = result
        return result
    }

    private static func performFaceDetection(url: URL) -> FaceDetectionResult {
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(url: url, options: [:])
        guard (try? handler.perform([landmarksRequest])) != nil,
              let observations = landmarksRequest.results, !observations.isEmpty
        else {
            return .none
        }

        var hasClosedEyes = false
        for face in observations {
            if isEyeClosed(face) {
                hasClosedEyes = true
                break
            }
        }

        return FaceDetectionResult(faceCount: observations.count, hasClosedEyes: hasClosedEyes)
    }

    /// Estimates whether eyes are closed by comparing the vertical span of the eye
    /// landmark region to its horizontal span. A ratio below ~0.15 suggests closure.
    private static func isEyeClosed(_ face: VNFaceObservation) -> Bool {
        guard let landmarks = face.landmarks else { return false }
        let eyeRegions = [landmarks.leftEye, landmarks.rightEye].compactMap { $0 }
        for eye in eyeRegions {
            let points = eye.normalizedPoints
            guard points.count >= 4 else { continue }
            let minY = points.map(\.y).min() ?? 0
            let maxY = points.map(\.y).max() ?? 1
            let minX = points.map(\.x).min() ?? 0
            let maxX = points.map(\.x).max() ?? 1
            let verticalSpan = maxY - minY
            let horizontalSpan = maxX - minX
            guard horizontalSpan > 0.001 else { continue }
            let ratio = verticalSpan / horizontalSpan
            if ratio < 0.15 { return true }
        }
        return false
    }

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
