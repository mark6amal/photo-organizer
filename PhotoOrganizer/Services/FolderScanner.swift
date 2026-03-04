import Foundation

enum FolderScanner {
    static func scan(url: URL) async throws -> [Photo] {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]

            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [] }

            // Group files by base path (without extension), lowercased for case-insensitivity
            var buckets: [String: [URL]] = [:]

            while let nextObject = enumerator.nextObject() {
                guard let fileURL = nextObject as? URL else { continue }
                let ext = fileURL.pathExtension.lowercased()
                guard rawExtensions.contains(ext) || jpegExtensions.contains(ext) else { continue }
                guard (try? fileURL.resourceValues(forKeys: resourceKeys))?.isRegularFile == true else { continue }

                let key = fileURL.deletingPathExtension().path.lowercased()
                buckets[key, default: []].append(fileURL)
            }

            var photos: [Photo] = []
            photos.reserveCapacity(buckets.count)

            for (_, urls) in buckets {
                let raws = urls.filter { rawExtensions.contains($0.pathExtension.lowercased()) }
                let jpegs = urls.filter { jpegExtensions.contains($0.pathExtension.lowercased()) }

                if let raw = raws.first {
                    // RAW with optional JPEG sidecar — show as one entry
                    photos.append(Photo(url: raw, jpegPairURL: jpegs.first))
                } else if let jpeg = jpegs.first {
                    photos.append(Photo(url: jpeg))
                }
            }

            photos.sort {
                $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }

            return photos
        }.value
    }
}
