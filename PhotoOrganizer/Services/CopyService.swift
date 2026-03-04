import Foundation

enum CopyService {
    struct Progress: Sendable {
        let completed: Int
        let total: Int
        let currentFileName: String
        var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    }

    struct ExportOptions: Sendable {
        var flatten: Bool = true
        var writeXMP: Bool = false
        var renamePattern: String = ""
        var decisions: [UUID: DecisionState] = [:]
        var ratings: [UUID: Int] = [:]
    }

    /// Copies winners (RAW + JPEG sidecar if paired) to `destination`.
    /// Yields progress after each file is copied.
    static func export(
        photos: [Photo],
        to destination: URL,
        sourceRoot: URL,
        options: ExportOptions
    ) -> AsyncStream<Progress> {
        AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                let fm = FileManager.default

                // Count total files (each RAW pair = 2 files)
                let total = photos.reduce(0) { $0 + ($1.jpegPairURL != nil ? 2 : 1) }
                var completed = 0

                func resolveDestURL(for src: URL, sequenceIndex: Int) -> URL {
                    let finalName = resolvedFileName(
                        for: src,
                        sequenceIndex: sequenceIndex,
                        pattern: options.renamePattern
                    )
                    if options.flatten {
                        return destination.appendingPathComponent(finalName)
                    } else {
                        let srcPath = src.standardizedFileURL.path
                        let rootPath = sourceRoot.standardizedFileURL.path
                        if srcPath.hasPrefix(rootPath) {
                            let relative = String(srcPath.dropFirst(rootPath.count))
                            let relativeURL = URL(fileURLWithPath: relative, relativeTo: destination)
                            if !options.renamePattern.isEmpty {
                                return relativeURL.deletingLastPathComponent()
                                    .appendingPathComponent(finalName)
                            }
                            return relativeURL.standardizedFileURL
                        }
                        return destination.appendingPathComponent(finalName)
                    }
                }

                func copyFile(_ src: URL, sequenceIndex: Int, photoID: UUID?) {
                    let destURL = resolveDestURL(for: src, sequenceIndex: sequenceIndex)
                    let dir = destURL.deletingLastPathComponent()
                    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    if fm.fileExists(atPath: destURL.path) {
                        try? fm.removeItem(at: destURL)
                    }
                    try? fm.copyItem(at: src, to: destURL)

                    if options.writeXMP, let pid = photoID {
                        let decision = options.decisions[pid] ?? .undecided
                        let rating = options.ratings[pid] ?? 0
                        XMPService.writeSidecar(for: destURL, decision: decision, rating: rating)
                    }

                    completed += 1
                    continuation.yield(Progress(
                        completed: completed,
                        total: total,
                        currentFileName: src.lastPathComponent
                    ))
                }

                for (index, photo) in photos.enumerated() {
                    copyFile(photo.url, sequenceIndex: index + 1, photoID: photo.id)
                    if let jpeg = photo.jpegPairURL {
                        copyFile(jpeg, sequenceIndex: index + 1, photoID: photo.id)
                    }
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Rename Pattern

    /// Resolves a filename using a pattern with tokens:
    ///   {name}  → original filename without extension
    ///   {seq}   → zero-padded sequence number
    ///   {ext}   → original file extension (with dot)
    ///   {date}  → today's date as YYYYMMDD
    private static func resolvedFileName(
        for url: URL,
        sequenceIndex: Int,
        pattern: String
    ) -> String {
        guard !pattern.isEmpty else { return url.lastPathComponent }
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let paddedSeq = String(format: "%04d", sequenceIndex)
        let dateStr: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd"
            return f.string(from: Date())
        }()
        let name = pattern
            .replacingOccurrences(of: "{name}", with: baseName)
            .replacingOccurrences(of: "{seq}", with: paddedSeq)
            .replacingOccurrences(of: "{date}", with: dateStr)
        let finalExt = ext.isEmpty ? "" : ".\(ext)"
        // If pattern already ends with the extension token or the ext, don't double-add
        if name.hasSuffix(finalExt) || ext.isEmpty {
            return name
        }
        return name + finalExt
    }
}
