import Foundation

enum DecisionState: String, Codable, Sendable {
    case undecided
    case kept
    case rejected
}

struct PhotoQualitySignals: Sendable {
    let sharpnessScore: Float?
    let focusScore: Int?
    let sharpnessLabel: String
    let exposureLabel: String
    let hasHighlightClipping: Bool
    let hasShadowClipping: Bool
    let recoverabilityHint: String
    let isNearDuplicate: Bool

    var badges: [String] {
        var values = [sharpnessLabel, exposureLabel]
        if hasHighlightClipping { values.append("Highlights clipped") }
        if hasShadowClipping { values.append("Shadows crushed") }
        if isNearDuplicate { values.append("Likely duplicate") }
        values.append(recoverabilityHint)
        return values
    }
}

@MainActor
@Observable
final class AppState {

    enum ViewMode { case filmstrip, grid }
    enum SimilarityMode: String, CaseIterable, Identifiable {
        case fastBurst
        case balanced
        case thorough

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fastBurst: return "Fast"
            case .balanced: return "Balanced"
            case .thorough: return "Thorough"
            }
        }

        var helpText: String {
            switch self {
            case .fastBurst:
                return "Compare adjacent burst frames only. Lowest CPU."
            case .balanced:
                return "Compare within a small local window. Good default."
            case .thorough:
                return "Compare all pairs inside each moment. Slowest."
            }
        }
    }

    // MARK: - State

    var sourceURL: URL?
    var photos: [Photo] = []
    var photoDecisions: [UUID: DecisionState] = [:]
    var rounds: [SelectionRound] = []
    var isScanning = false
    var scanError: String?
    var viewMode: ViewMode = .filmstrip
    var currentPhotoIndex: Int = 0

    // Grouping
    var groupingEnabled: Bool = false
    var groups: [PhotoGroup] = []
    var isGrouping: Bool = false
    var groupGapThreshold: TimeInterval = 5

    // Visual Similarity
    var similarityEnabled: Bool = false
    var isSimilarityComputing: Bool = false
    var similarityThreshold: Float = 0.06
    var similarityMode: SimilarityMode = .balanced
    var similarityProgressCompleted: Int = 0
    var similarityProgressTotal: Int = 0

    // Histogram
    var histogramEnabled: Bool = false

    // Loupe
    var loupeEnabled: Bool = false

    // Metadata panel
    var metadataEnabled: Bool = false

    // Analysis
    var sharpnessScores: [UUID: Float] = [:]
    var qualitySignalsByPhotoID: [UUID: PhotoQualitySignals] = [:]

    // MARK: - Compatibility

    var selectedIDs: Set<UUID> {
        get {
            Set(
                photoDecisions.compactMap { entry in
                    entry.value == .kept ? entry.key : nil
                }
            )
        }
        set {
            let validIDs = Set(photos.map(\.id))
            for id in validIDs {
                if newValue.contains(id) {
                    photoDecisions[id] = .kept
                } else if photoDecisions[id] == .kept {
                    photoDecisions.removeValue(forKey: id)
                }
            }
        }
    }

    // MARK: - Derived

    var currentPhoto: Photo? {
        photos.indices.contains(currentPhotoIndex) ? photos[currentPhotoIndex] : nil
    }

    var keptPhotoIDs: Set<UUID> { selectedIDs }
    var keptPhotos: [Photo] { photos.filter { isKept($0) } }
    var rejectedPhotos: [Photo] { photos.filter { isRejected($0) } }
    var undecidedPhotos: [Photo] { photos.filter { decisionState(for: $0) == .undecided } }

    var selectedPhotos: [Photo] { keptPhotos }
    var hasKeptPhotos: Bool { !keptPhotoIDs.isEmpty }
    var hasSelection: Bool { hasKeptPhotos }
    var keptCount: Int { keptPhotoIDs.count }
    var selectionCount: Int { keptCount }

    var similarityProgressFraction: Double {
        guard similarityProgressTotal > 0 else { return 0 }
        return Double(similarityProgressCompleted) / Double(similarityProgressTotal)
    }

    var similarityProgressText: String {
        guard similarityProgressTotal > 0 else { return "0 / 0 scores" }
        return "\(similarityProgressCompleted) / \(similarityProgressTotal) scores"
    }

    var currentGroupIndex: Int? {
        guard groupingEnabled, let current = currentPhoto else { return nil }
        return groups.firstIndex { $0.photos.contains { $0.id == current.id } }
    }

    var currentMomentIndex: Int? {
        if groupingEnabled {
            return currentGroupIndex
        }
        return currentPhoto == nil ? nil : currentPhotoIndex
    }

    var momentCount: Int {
        if groupingEnabled, !groups.isEmpty {
            return groups.count
        }
        return photos.count
    }

    var currentPhotoIndexInGroup: Int? {
        guard let gi = currentGroupIndex, let current = currentPhoto else { return nil }
        return groups[gi].photos.firstIndex { $0.id == current.id }.map { $0 + 1 }
    }

    var currentPhotoIndexInMoment: Int? {
        if groupingEnabled {
            return currentPhotoIndexInGroup
        }
        return currentPhoto == nil ? nil : 1
    }

    var currentGroupPhotoCount: Int? {
        guard let gi = currentGroupIndex else { return nil }
        return groups[gi].photos.count
    }

    var currentMomentPhotoCount: Int? {
        if groupingEnabled {
            return currentGroupPhotoCount
        }
        return currentPhoto == nil ? nil : 1
    }

    var currentMoment: PhotoGroup? {
        if groupingEnabled, let gi = currentGroupIndex {
            return groups[gi]
        }
        guard let current = currentPhoto else { return nil }
        return PhotoGroup(
            id: current.id,
            number: currentPhotoIndex + 1,
            photos: [current],
            startDate: nil,
            endDate: nil
        )
    }

    private var visualClusterSequence: [[Photo]] {
        guard groupingEnabled, !groups.isEmpty else { return [] }

        return groups.flatMap { group in
            if similarityEnabled, let clusters = group.clusters, !clusters.isEmpty {
                return clusters
            }
            return group.photos.isEmpty ? [] : [group.photos]
        }
    }

    var filmstripInfoText: String {
        guard let momentIndex = currentMomentIndex else {
            return "No moment"
        }

        if let pos = currentPhotoIndexInMoment,
           let total = currentMomentPhotoCount,
           total > 1 {
            return "Moment \(momentIndex + 1) of \(momentCount) · Photo \(pos)/\(total)"
        }
        return "Moment \(momentIndex + 1) of \(momentCount)"
    }

    // MARK: - Decisions

    func decisionState(for photo: Photo) -> DecisionState {
        photoDecisions[photo.id] ?? .undecided
    }

    func isKept(_ photo: Photo) -> Bool {
        decisionState(for: photo) == .kept
    }

    func isRejected(_ photo: Photo) -> Bool {
        decisionState(for: photo) == .rejected
    }

    func isSelected(_ photo: Photo) -> Bool {
        isKept(photo)
    }

    func selectedInGroup(_ group: PhotoGroup) -> Int {
        group.photos.filter { isKept($0) }.count
    }

    func setDecision(_ state: DecisionState, for photo: Photo) {
        if state == .undecided {
            photoDecisions.removeValue(forKey: photo.id)
        } else {
            photoDecisions[photo.id] = state
        }
    }

    func clearDecision(for photo: Photo) {
        photoDecisions.removeValue(forKey: photo.id)
    }

    func toggleSelected(_ photo: Photo) {
        if isKept(photo) {
            clearDecision(for: photo)
        } else {
            setDecision(.kept, for: photo)
        }
    }

    func toggleCurrentPhoto() {
        guard let photo = currentPhoto else { return }
        toggleSelected(photo)
    }

    func markCurrentPhotoKept() {
        guard let photo = currentPhoto else { return }
        setDecision(.kept, for: photo)
    }

    func markCurrentPhotoRejected() {
        guard let photo = currentPhoto else { return }
        setDecision(.rejected, for: photo)
    }

    func clearCurrentPhotoDecision() {
        guard let photo = currentPhoto else { return }
        clearDecision(for: photo)
    }

    // MARK: - Navigation

    func navigateFilmstrip(by delta: Int) {
        guard !photos.isEmpty else { return }
        currentPhotoIndex = max(0, min(photos.count - 1, currentPhotoIndex + delta))
    }

    func navigateMoment(by delta: Int) {
        guard !photos.isEmpty else { return }
        if let current = currentPhoto,
           let clusterIndex = visualClusterSequence.firstIndex(where: { cluster in
               cluster.contains(where: { $0.id == current.id })
           }) {
            let newIndex = max(0, min(visualClusterSequence.count - 1, clusterIndex + delta))
            if newIndex != clusterIndex,
               let target = visualClusterSequence[newIndex].first,
               let flatIdx = photos.firstIndex(where: { $0.id == target.id }) {
                currentPhotoIndex = flatIdx
                return
            }
        }

        guard groupingEnabled, let gi = currentGroupIndex else {
            navigateFilmstrip(by: delta)
            return
        }
        let newGI = max(0, min(groups.count - 1, gi + delta))
        let target = groups[newGI].photos[0]
        if let flatIdx = photos.firstIndex(where: { $0.id == target.id }) {
            currentPhotoIndex = flatIdx
        }
    }

    func navigateGroup(by delta: Int) {
        navigateMoment(by: delta)
    }

    func navigateWithinGroup(by delta: Int) {
        guard !photos.isEmpty else { return }
        guard groupingEnabled, let gi = currentGroupIndex, let current = currentPhoto else {
            navigateFilmstrip(by: delta)
            return
        }
        let groupPhotos = groups[gi].photos
        guard let posInGroup = groupPhotos.firstIndex(where: { $0.id == current.id }) else { return }
        let newPos = max(0, min(groupPhotos.count - 1, posInGroup + delta))
        let target = groupPhotos[newPos]
        if let flatIdx = photos.firstIndex(where: { $0.id == target.id }) {
            currentPhotoIndex = flatIdx
        }
    }

    func navigateWithinMoment(by delta: Int) {
        navigateWithinGroup(by: delta)
    }

    // MARK: - Grouping

    func computeGroups() async {
        guard groupingEnabled, !photos.isEmpty else {
            groups = []
            clearDuplicateFlags()
            return
        }
        isGrouping = true
        groups = await GroupingService.group(photos: photos, gapThreshold: groupGapThreshold)
        isGrouping = false
        if similarityEnabled {
            await computeSimilarity()
        } else {
            refreshDuplicateFlags()
        }
    }

    // MARK: - Visual Similarity

    func computeSimilarity() async {
        guard similarityEnabled, !groups.isEmpty else {
            for i in 0..<groups.count { groups[i].clusters = nil }
            clearDuplicateFlags()
            similarityProgressCompleted = 0
            similarityProgressTotal = 0
            return
        }
        isSimilarityComputing = true
        similarityProgressCompleted = 0
        similarityProgressTotal = groups.reduce(into: 0) { partial, group in
            partial += PixelSimilarityService.comparisonCount(
                for: group.photos.count,
                mode: similarityMode
            )
        }

        if let sourceURL,
           let cached = await SimilarityCacheService.shared.load(
               folderURL: sourceURL,
               photos: photos,
               mode: similarityMode,
               threshold: similarityThreshold,
               groupGapThreshold: groupGapThreshold
           ) {
            applyCachedSimilarity(cached)
            similarityProgressCompleted = similarityProgressTotal
            isSimilarityComputing = false
            return
        }

        var sharpnessByPath: [String: Float] = [:]
        for i in 0..<groups.count {
            similarityProgressCompleted += PixelSimilarityService.comparisonCount(
                for: groups[i].photos.count,
                mode: similarityMode
            )
            groups[i].clusters = await PixelSimilarityService.shared.cluster(
                photos: groups[i].photos,
                mode: similarityMode,
                threshold: similarityThreshold
            )
            for photo in groups[i].photos {
                if let score = await PixelSimilarityService.shared.sharpness(for: photo.thumbnailSourceURL) {
                    sharpnessScores[photo.id] = score
                    sharpnessByPath[photo.thumbnailSourceURL.path] = score

                    if let existing = qualitySignalsByPhotoID[photo.id] {
                        qualitySignalsByPhotoID[photo.id] = PhotoQualitySignals(
                            sharpnessScore: score,
                            focusScore: Self.focusScore(for: score),
                            sharpnessLabel: Self.sharpnessLabel(for: score),
                            exposureLabel: existing.exposureLabel,
                            hasHighlightClipping: existing.hasHighlightClipping,
                            hasShadowClipping: existing.hasShadowClipping,
                            recoverabilityHint: existing.recoverabilityHint,
                            isNearDuplicate: existing.isNearDuplicate
                        )
                    }
                }
            }
        }

        if let sourceURL {
            await SimilarityCacheService.shared.save(
                folderURL: sourceURL,
                photos: photos,
                mode: similarityMode,
                threshold: similarityThreshold,
                groupGapThreshold: groupGapThreshold,
                groups: groups,
                sharpnessByPath: sharpnessByPath
            )
        }
        refreshDuplicateFlags()
        isSimilarityComputing = false
    }

    func toggleGroupCollapsed(_ group: PhotoGroup) {
        guard let i = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[i].isCollapsed.toggle()
    }

    // MARK: - Quality Signals

    func qualitySignals(for photo: Photo) -> PhotoQualitySignals? {
        qualitySignalsByPhotoID[photo.id]
    }

    func ensureQualitySignals(for photo: Photo) async {
        let isNearDuplicate = duplicateClusterSize(for: photo) > 1
        if let existing = qualitySignalsByPhotoID[photo.id] {
            if existing.isNearDuplicate != isNearDuplicate {
                qualitySignalsByPhotoID[photo.id] = PhotoQualitySignals(
                    sharpnessScore: existing.sharpnessScore,
                    focusScore: existing.focusScore,
                    sharpnessLabel: existing.sharpnessLabel,
                    exposureLabel: existing.exposureLabel,
                    hasHighlightClipping: existing.hasHighlightClipping,
                    hasShadowClipping: existing.hasShadowClipping,
                    recoverabilityHint: existing.recoverabilityHint,
                    isNearDuplicate: isNearDuplicate
                )
            }
            return
        }

        async let sharpnessTask = PixelSimilarityService.shared.sharpness(for: photo.thumbnailSourceURL)
        async let histogramTask = HistogramService.shared.histogram(for: photo.thumbnailSourceURL)
        let sharpness = await sharpnessTask
        let histogram = await histogramTask

        if let sharpness {
            sharpnessScores[photo.id] = sharpness
        }

        qualitySignalsByPhotoID[photo.id] = Self.buildQualitySignals(
            for: photo,
            sharpnessScore: sharpness,
            histogram: histogram,
            isNearDuplicate: isNearDuplicate
        )
    }

    private func duplicateClusterSize(for photo: Photo) -> Int {
        guard groupingEnabled, similarityEnabled else { return 0 }
        for group in groups {
            guard let clusters = group.clusters else { continue }
            for cluster in clusters where cluster.contains(where: { $0.id == photo.id }) {
                return cluster.count
            }
        }
        return 0
    }

    private func clearDuplicateFlags() {
        for (id, signals) in qualitySignalsByPhotoID {
            guard signals.isNearDuplicate else { continue }
            qualitySignalsByPhotoID[id] = PhotoQualitySignals(
                sharpnessScore: signals.sharpnessScore,
                focusScore: signals.focusScore,
                sharpnessLabel: signals.sharpnessLabel,
                exposureLabel: signals.exposureLabel,
                hasHighlightClipping: signals.hasHighlightClipping,
                hasShadowClipping: signals.hasShadowClipping,
                recoverabilityHint: signals.recoverabilityHint,
                isNearDuplicate: false
            )
        }
    }

    private func refreshDuplicateFlags() {
        for (id, signals) in qualitySignalsByPhotoID {
            guard let photo = photos.first(where: { $0.id == id }) else { continue }
            let isNearDuplicate = duplicateClusterSize(for: photo) > 1
            guard signals.isNearDuplicate != isNearDuplicate else { continue }
            qualitySignalsByPhotoID[id] = PhotoQualitySignals(
                sharpnessScore: signals.sharpnessScore,
                focusScore: signals.focusScore,
                sharpnessLabel: signals.sharpnessLabel,
                exposureLabel: signals.exposureLabel,
                hasHighlightClipping: signals.hasHighlightClipping,
                hasShadowClipping: signals.hasShadowClipping,
                recoverabilityHint: signals.recoverabilityHint,
                isNearDuplicate: isNearDuplicate
            )
        }
    }

    private static func buildQualitySignals(
        for photo: Photo,
        sharpnessScore: Float?,
        histogram: HistogramData?,
        isNearDuplicate: Bool
    ) -> PhotoQualitySignals {
        let sharpnessLabel = sharpnessLabel(for: sharpnessScore)
        let histogramSummary = histogram.map { Self.histogramSummary(for: $0) } ?? HistogramSummary.neutral
        return PhotoQualitySignals(
            sharpnessScore: sharpnessScore,
            focusScore: focusScore(for: sharpnessScore),
            sharpnessLabel: sharpnessLabel,
            exposureLabel: exposureLabel(for: histogramSummary.averageLuma),
            hasHighlightClipping: histogramSummary.highlightClip,
            hasShadowClipping: histogramSummary.shadowClip,
            recoverabilityHint: recoverabilityHint(
                isRAW: photo.isRAW,
                highlightClip: histogramSummary.highlightClip,
                shadowClip: histogramSummary.shadowClip,
                averageLuma: histogramSummary.averageLuma
            ),
            isNearDuplicate: isNearDuplicate
        )
    }

    private struct HistogramSummary {
        let averageLuma: Float
        let highlightClip: Bool
        let shadowClip: Bool

        static let neutral = HistogramSummary(
            averageLuma: 0.5,
            highlightClip: false,
            shadowClip: false
        )
    }

    private static func histogramSummary(for histogram: HistogramData) -> HistogramSummary {
        let values = histogram.luma
        let total = max(values.reduce(Float.zero, +), 0.0001)
        let weighted = values.enumerated().reduce(Float.zero) { partial, entry in
            let normalizedIndex = Float(entry.offset) / Float(max(values.count - 1, 1))
            return partial + (normalizedIndex * entry.element)
        } / total

        let shadowEnergy = values.prefix(4).reduce(Float.zero, +)
        let highlightEnergy = values.suffix(4).reduce(Float.zero, +)
        return HistogramSummary(
            averageLuma: weighted,
            highlightClip: highlightEnergy > 1.15,
            shadowClip: shadowEnergy > 1.15
        )
    }

    private static func sharpnessLabel(for score: Float?) -> String {
        guard let score else { return "Sharpness unknown" }
        switch score {
        case ..<0.02:
            return "Soft"
        case ..<0.06:
            return "Borderline"
        default:
            return "Sharp"
        }
    }

    private static func focusScore(for sharpness: Float?) -> Int? {
        guard let sharpness else { return nil }

        let capped = min(max(sharpness, 0), 0.12)
        let normalized = log1p(Double(capped * 100)) / log1p(12)
        return Int((normalized * 100).rounded())
    }

    private static func exposureLabel(for averageLuma: Float) -> String {
        switch averageLuma {
        case ..<0.18:
            return "Heavily underexposed"
        case ..<0.36:
            return "Slightly dark"
        case ..<0.68:
            return "Balanced"
        case ..<0.82:
            return "Slightly bright"
        default:
            return "Heavily overexposed"
        }
    }

    private static func recoverabilityHint(
        isRAW: Bool,
        highlightClip: Bool,
        shadowClip: Bool,
        averageLuma: Float
    ) -> String {
        if isRAW {
            if highlightClip || shadowClip {
                return "Likely recoverable"
            }
            if averageLuma < 0.18 || averageLuma > 0.82 {
                return "Moderate recovery room"
            }
            return "Healthy editing headroom"
        }

        if highlightClip && shadowClip {
            return "Limited recovery"
        }
        if highlightClip || shadowClip {
            return "Some recovery possible"
        }
        return "Good JPEG latitude"
    }

    // MARK: - Rounds

    func startNewRound() {
        guard hasKeptPhotos else { return }
        let round = SelectionRound(
            id: UUID(),
            number: rounds.count + 1,
            sourcePhotos: photos,
            keptIDs: keptPhotoIDs,
            date: Date()
        )
        rounds.append(round)
        photos = round.winners
        photoDecisions = [:]
        currentPhotoIndex = 0
        groups = []
        qualitySignalsByPhotoID = [:]
        sharpnessScores = [:]
        SessionStore.save(self)
    }

    // MARK: - Loading

    func loadPhotos(from url: URL) async {
        isScanning = true
        scanError = nil
        similarityProgressCompleted = 0
        similarityProgressTotal = 0
        await ThumbnailService.shared.clearAll()
        await HistogramService.shared.clearCache()
        await PixelSimilarityService.shared.clearCache()
        photos = []
        photoDecisions = [:]
        currentPhotoIndex = 0
        groups = []
        sharpnessScores = [:]
        qualitySignalsByPhotoID = [:]
        do {
            photos = try await FolderScanner.scan(url: url)
        } catch {
            scanError = error.localizedDescription
        }
        isScanning = false
        sourceURL = url
        RecentFolders.add(url)
        SessionStore.save(self)
    }

    func reset() {
        sourceURL = nil
        photos = []
        photoDecisions = [:]
        rounds = []
        scanError = nil
        isScanning = false
        currentPhotoIndex = 0
        groups = []
        groupingEnabled = false
        similarityEnabled = false
        histogramEnabled = false
        loupeEnabled = false
        metadataEnabled = false
        sharpnessScores = [:]
        qualitySignalsByPhotoID = [:]
        similarityProgressCompleted = 0
        similarityProgressTotal = 0
        Task {
            await ThumbnailService.shared.clearAll()
            await HistogramService.shared.clearCache()
            await PixelSimilarityService.shared.clearCache()
        }
        SessionStore.clear()
    }

    private func applyCachedSimilarity(_ cached: SimilarityCacheService.CachedAnalysis) {
        let photosByPath = Dictionary(uniqueKeysWithValues: photos.map {
            ($0.thumbnailSourceURL.path, $0)
        })

        for i in 0..<groups.count {
            let clusterPaths = cached.groupClustersByIndex[i] ?? [groups[i].photos.map(\.thumbnailSourceURL.path)]
            groups[i].clusters = clusterPaths
                .map { $0.compactMap { photosByPath[$0] } }
                .filter { !$0.isEmpty }
        }

        for photo in photos {
            if let score = cached.sharpnessByPath[photo.thumbnailSourceURL.path] {
                sharpnessScores[photo.id] = score
            }
        }
    }
}
