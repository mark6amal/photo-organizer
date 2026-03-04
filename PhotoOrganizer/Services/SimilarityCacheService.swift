import Foundation
import CryptoKit

actor SimilarityCacheService {
    static let shared = SimilarityCacheService()

    struct CachedAnalysis {
        let groupClustersByIndex: [Int: [[String]]]
        let sharpnessByPath: [String: Float]
    }

    private static let cacheVersion = 1

    func load(
        folderURL: URL,
        photos: [Photo],
        mode: AppState.SimilarityMode,
        threshold: Float,
        groupGapThreshold: TimeInterval
    ) async -> CachedAnalysis? {
        guard let cacheURL = cacheFileURL(
            folderURL: folderURL,
            photos: photos,
            mode: mode,
            threshold: threshold,
            groupGapThreshold: groupGapThreshold
        ) else {
            return nil
        }

        guard
            let data = try? Data(contentsOf: cacheURL),
            let payload = try? JSONDecoder().decode(CachePayload.self, from: data),
            payload.version == Self.cacheVersion
        else {
            return nil
        }

        let clusters = Dictionary(uniqueKeysWithValues: payload.groups.map {
            ($0.groupIndex, $0.clusters)
        })

        return CachedAnalysis(
            groupClustersByIndex: clusters,
            sharpnessByPath: payload.sharpnessByPath
        )
    }

    func save(
        folderURL: URL,
        photos: [Photo],
        mode: AppState.SimilarityMode,
        threshold: Float,
        groupGapThreshold: TimeInterval,
        groups: [PhotoGroup],
        sharpnessByPath: [String: Float]
    ) async {
        guard let cacheURL = cacheFileURL(
            folderURL: folderURL,
            photos: photos,
            mode: mode,
            threshold: threshold,
            groupGapThreshold: groupGapThreshold
        ) else {
            return
        }

        let payload = CachePayload(
            version: Self.cacheVersion,
            folderPath: folderURL.path,
            mode: mode.rawValue,
            threshold: threshold,
            groupGapThreshold: groupGapThreshold,
            groups: groups.enumerated().map { index, group in
                CachedGroup(
                    groupIndex: index,
                    clusters: (group.clusters ?? [group.photos]).map { cluster in
                        cluster.map { $0.thumbnailSourceURL.path }
                    }
                )
            },
            sharpnessByPath: sharpnessByPath
        )

        guard let data = try? JSONEncoder().encode(payload) else { return }
        let directory = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func cacheFileURL(
        folderURL: URL,
        photos: [Photo],
        mode: AppState.SimilarityMode,
        threshold: Float,
        groupGapThreshold: TimeInterval
    ) -> URL? {
        guard let root = cacheRootDirectory() else { return nil }

        let key = Self.cacheKey(
            folderURL: folderURL,
            photos: photos,
            mode: mode,
            threshold: threshold,
            groupGapThreshold: groupGapThreshold
        )

        return root.appending(path: "\(key).json")
    }

    private func cacheRootDirectory() -> URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let root = support
            .appending(path: "PhotoOrganizer")
            .appending(path: "SimilarityCache")

        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func cacheKey(
        folderURL: URL,
        photos: [Photo],
        mode: AppState.SimilarityMode,
        threshold: Float,
        groupGapThreshold: TimeInterval
    ) -> String {
        let manifestLines = photos.map { photo in
            let url = photo.thumbnailSourceURL
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            return "\(url.path)|\(size)|\(modified)"
        }

        let raw = """
        v=\(cacheVersion)
        folder=\(folderURL.path)
        mode=\(mode.rawValue)
        threshold=\(String(format: "%.4f", threshold))
        gap=\(String(format: "%.4f", groupGapThreshold))
        files=\(manifestLines.joined(separator: "\n"))
        """

        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct CachePayload: Codable {
    let version: Int
    let folderPath: String
    let mode: String
    let threshold: Float
    let groupGapThreshold: TimeInterval
    let groups: [CachedGroup]
    let sharpnessByPath: [String: Float]
}

private struct CachedGroup: Codable {
    let groupIndex: Int
    let clusters: [[String]]
}
