import Foundation

enum CopyService {
    struct Progress: Sendable {
        let completed: Int
        let total: Int
        let currentFileName: String
        var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    }

    /// Copies winners (RAW + JPEG sidecar if paired) to `destination`.
    /// Yields progress after each file is copied.
    static func export(
        photos: [Photo],
        to destination: URL,
        flatten: Bool,
        sourceRoot: URL
    ) -> AsyncStream<Progress> {
        AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                let fm = FileManager.default

                // Count total files (each RAW pair = 2 files)
                let total = photos.reduce(0) { $0 + ($1.jpegPairURL != nil ? 2 : 1) }
                var completed = 0

                func copyFile(_ src: URL) {
                    let destURL: URL
                    if flatten {
                        destURL = destination.appendingPathComponent(src.lastPathComponent)
                    } else {
                        // Preserve path relative to source root
                        let srcPath = src.standardizedFileURL.path
                        let rootPath = sourceRoot.standardizedFileURL.path
                        let relative = srcPath.hasPrefix(rootPath)
                            ? String(srcPath.dropFirst(rootPath.count))
                            : src.lastPathComponent
                        destURL = destination.appendingPathComponent(relative)
                    }

                    let dir = destURL.deletingLastPathComponent()
                    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

                    if fm.fileExists(atPath: destURL.path) {
                        try? fm.removeItem(at: destURL)
                    }
                    try? fm.copyItem(at: src, to: destURL)

                    completed += 1
                    continuation.yield(Progress(
                        completed: completed,
                        total: total,
                        currentFileName: src.lastPathComponent
                    ))
                }

                for photo in photos {
                    copyFile(photo.url)
                    if let jpeg = photo.jpegPairURL {
                        copyFile(jpeg)
                    }
                }

                continuation.finish()
            }
        }
    }
}
