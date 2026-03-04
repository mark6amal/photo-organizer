import Foundation

enum DecisionState: String, Codable, Sendable {
    case undecided
    case kept
    case rejected
}

struct PhotoQualitySignals: Sendable {
    var sharpnessScore: Float?
    var sharpnessLabel: String
    var exposureLabel: String
    var hasHighlightClipping: Bool
    var hasShadowClipping: Bool
    var recoverabilityHint: String
    var isNearDuplicate: Bool
    var faceCount: Int = 0
    var hasClosedEyes: Bool = false
    var noiseLabel: String = ""
    var isBestPick: Bool = false

    var badges: [String] {
        var values = [sharpnessLabel, exposureLabel]
        if hasHighlightClipping { values.append("Highlights clipped") }
        if hasShadowClipping { values.append("Shadows crushed") }
        if isNearDuplicate { values.append("Likely duplicate") }
        values.append(recoverabilityHint)
        if faceCount == 1 { values.append("1 face detected") }
        else if faceCount > 1 { values.append("\(faceCount) faces detected") }
        if hasClosedEyes { values.append("Eyes may be closed") }
        if !noiseLabel.isEmpty { values.append(noiseLabel) }
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

    enum DecisionFilter: String, CaseIterable, Identifiable {
        case all
        case kept
        case rejected
        case undecided

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "All"
            case .kept: return "Kept"
            case .rejected: return "Rejected"
            case .undecided: return "Undecided"
            }
        }

        var systemImage: String {
            switch self {
            case .all: return "photo.stack"
            case .kept: return "checkmark.circle.fill"
            case .rejected: return "xmark.circle.fill"
            case .undecided: return "circle.dotted"
            }
        }
    }

    // MARK: - State

    var sourceURL: URL?
    var photos: [Photo] = []
    var photoDecisions: [UUID: DecisionState] = [:]
    var photoRatings: [UUID: Int] = [:]
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

    // Filter
    var activeFilter: DecisionFilter = .all

    // Auto-advance
    var autoAdvanceEnabled: Bool = false

    // Comparison
    var comparisonEnabled: Bool = false
    var comparisonPhotoID: UUID? = nil

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

    var comparisonPhoto: Photo? {
        guard let id = comparisonPhotoID else { return nil }
        return photos.first { $0.id == id }
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

    var filteredPhotoIndices: [Int] {
        switch activeFilter {
        case .all:
            return Array(photos.indices)
        case .kept:
            return photos.indices.filter { isKept(photos[$0]) }
        case .rejected:
            return photos.indices.filter { isRejected(photos[$0]) }
        case .undecided:
            return photos.indices.filter { decisionState(for: photos[$0]) == .undecided }
        }
    }

    var filteredPhotoCount: Int {
        activeFilter == .all ? photos.count : filteredPhotoIndices.count
    }

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

        let filterSuffix = activeFilter != .all ? " · \(activeFilter.label)" : ""
        if let pos = currentPhotoIndexInMoment,
           let total = currentMomentPhotoCount,
           total > 1 {
            return "Moment \(momentIndex + 1) of \(momentCount) · Photo \(pos)/\(total)\(filterSuffix)"
        }
        return "Moment \(momentIndex + 1) of \(momentCount)\(filterSuffix)"
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
        if autoAdvanceEnabled { advanceAfterDecision() }
    }

    func markCurrentPhotoRejected() {
        guard let photo = currentPhoto else { return }
        setDecision(.rejected, for: photo)
        if autoAdvanceEnabled { advanceAfterDecision() }
    }

    func clearCurrentPhotoDecision() {
        guard let photo = currentPhoto else { return }
        clearDecision(for: photo)
    }

    private func advanceAfterDecision() {
        if activeFilter != .all {
            navigateFiltered(by: 1)
        } else {
            navigateMoment(by: 1)
        }
    }

    // MARK: - Star Ratings

    func rating(for photo: Photo) -> Int {
        photoRatings[photo.id] ?? 0
    }

    func setRating(_ rating: Int, for photo: Photo) {
        if rating == 0 {
            photoRatings.removeValue(forKey: photo.id)
        } else {
            photoRatings[photo.id] = max(1, min(5, rating))
        }
    }

    func setCurrentPhotoRating(_ rating: Int) {
        guard let photo = currentPhoto else { return }
        setRating(rating, for: photo)
    }

    // MARK: - Navigation

    func navigateFilmstrip(by delta: Int) {
        guard !photos.isEmpty else { return }
        currentPhotoIndex = max(0, min(photos.count - 1, currentPhotoIndex + delta))
    }

    func navigateFiltered(by delta: Int) {
        let indices = filteredPhotoIndices
        guard !indices.isEmpty else { return }
        if let pos = indices.firstIndex(of: currentPhotoIndex) {
            let newPos = max(0, min(indices.count - 1, pos + delta))
            currentPhotoIndex = indices[newPos]
        } else {
            currentPhotoIndex = delta >= 0 ? (indices.first ?? 0) : (indices.last ?? 0)
        }
    }

    func navigateMoment(by delta: Int) {
        guard !photos.isEmpty else { return }

        if activeFilter != .all {
            navigateFiltered(by: delta)
            return
        }

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

    // MARK: - Comparison

    func toggleComparison() {
        if comparisonEnabled {
            comparisonEnabled = false
            comparisonPhotoID = nil
        } else {
            comparisonEnabled = true
            // Default: compare against next photo in current moment or flat list
            if let current = currentPhoto,
               groupingEnabled,
               let gi = currentGroupIndex {
                let groupPhotos = groups[gi].photos
                if let posInGroup = groupPhotos.firstIndex(where: { $0.id == current.id }),
                   posInGroup + 1 < groupPhotos.count {
                    comparisonPhotoID = groupPhotos[posInGroup + 1].id
                } else {
                    comparisonPhotoID = photos.indices.contains(currentPhotoIndex + 1)
                        ? photos[currentPhotoIndex + 1].id : nil
                }
            } else {
                comparisonPhotoID = photos.indices.contains(currentPhotoIndex + 1)
                    ? photos[currentPhotoIndex + 1].id : nil
            }
        }
    }

    func cycleComparisonPhoto(by delta: Int) {
        guard comparisonEnabled, let currentID = comparisonPhotoID else { return }
        guard let idx = photos.firstIndex(where: { $0.id == currentID }) else { return }
        let newIdx = max(0, min(photos.count - 1, idx + delta))
        comparisonPhotoID = photos[newIdx].id
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
            refreshBestPickFlags()
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
                    qualitySignalsByPhotoID[photo.id]?.sharpnessScore = score
                    qualitySignalsByPhotoID[photo.id]?.sharpnessLabel = Self.sharpnessLabel(for: score)
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
        refreshBestPickFlags()
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
                qualitySignalsByPhotoID[photo.id]?.isNearDuplicate = isNearDuplicate
            }
            return
        }

        async let sharpnessTask = PixelSimilarityService.shared.sharpness(for: photo.thumbnailSourceURL)
        async let histogramTask = HistogramService.shared.histogram(for: photo.thumbnailSourceURL)
        async let noiseTask = PixelSimilarityService.shared.noiseEstimate(for: photo.thumbnailSourceURL)
        async let faceTask = VisionService.shared.detectFaces(for: photo.thumbnailSourceURL)

        let sharpness = await sharpnessTask
        let histogram = await histogramTask
        let noiseScore = await noiseTask
        let faceResult = await faceTask

        if let sharpness {
            sharpnessScores[photo.id] = sharpness
        }

        var signals = Self.buildQualitySignals(
            for: photo,
            sharpnessScore: sharpness,
            histogram: histogram,
            isNearDuplicate: isNearDuplicate
        )
        signals.noiseLabel = Self.noiseLabel(for: noiseScore)
        signals.faceCount = faceResult.faceCount
        signals.hasClosedEyes = faceResult.hasClosedEyes

        qualitySignalsByPhotoID[photo.id] = signals
    }

    // MARK: - Best Pick

    func isBestPick(_ photo: Photo) -> Bool {
        qualitySignalsByPhotoID[photo.id]?.isBestPick ?? false
    }

    private func refreshBestPickFlags() {
        // Clear all best pick flags first
        for id in qualitySignalsByPhotoID.keys {
            qualitySignalsByPhotoID[id]?.isBestPick = false
        }

        // Determine clusters to rank
        let clusterGroups: [[Photo]]
        if groupingEnabled, !groups.isEmpty, similarityEnabled {
            clusterGroups = groups.flatMap { group -> [[Photo]] in
                guard let clusters = group.clusters, !clusters.isEmpty else {
                    return [group.photos]
                }
                return clusters
            }
        } else if groupingEnabled, !groups.isEmpty {
            clusterGroups = groups.map(\.photos)
        } else {
            // No grouping: treat all photos as one cluster (no best pick needed)
            return
        }

        for cluster in clusterGroups where cluster.count > 1 {
            let bestID = bestPhotoID(in: cluster)
            qualitySignalsByPhotoID[bestID]?.isBestPick = true
        }
    }

    private func bestPhotoID(in photos: [Photo]) -> UUID {
        var bestID = photos[0].id
        var bestScore: Float = -Float.infinity

        for photo in photos {
            var score: Float = 0
            if let signals = qualitySignalsByPhotoID[photo.id] {
                // Sharpness contribution
                score += (signals.sharpnessScore ?? 0) * 100
                // Penalize clipping
                if signals.hasHighlightClipping { score -= 20 }
                if signals.hasShadowClipping { score -= 10 }
                // Reward balanced exposure
                let exposurePenalty: Float
                switch signals.exposureLabel {
                case "Balanced": exposurePenalty = 0
                case "Slightly dark", "Slightly bright": exposurePenalty = -5
                default: exposurePenalty = -20
                }
                score += exposurePenalty
                // Bonus for face detected (portrait sessions)
                if signals.faceCount > 0 { score += 5 }
                // Penalize closed eyes
                if signals.hasClosedEyes { score -= 30 }
            }
            // Bonus for higher star rating
            score += Float(photoRatings[photo.id] ?? 0) * 10

            if score > bestScore {
                bestScore = score
                bestID = photo.id
            }
        }
        return bestID
    }

    // MARK: - Private Quality Helpers

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
        for id in qualitySignalsByPhotoID.keys {
            qualitySignalsByPhotoID[id]?.isNearDuplicate = false
        }
    }

    private func refreshDuplicateFlags() {
        for (id, signals) in qualitySignalsByPhotoID {
            guard let photo = photos.first(where: { $0.id == id }) else { continue }
            let isNearDuplicate = duplicateClusterSize(for: photo) > 1
            guard signals.isNearDuplicate != isNearDuplicate else { continue }
            qualitySignalsByPhotoID[id]?.isNearDuplicate = isNearDuplicate
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

    private static func noiseLabel(for score: Float?) -> String {
        guard let score else { return "" }
        switch score {
        case ..<0.005:
            return "Clean"
        case ..<0.015:
            return "Moderate noise"
        default:
            return "Heavy noise"
        }
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
        photoRatings = [:]
        currentPhotoIndex = 0
        groups = []
        qualitySignalsByPhotoID = [:]
        sharpnessScores = [:]
        activeFilter = .all
        comparisonEnabled = false
        comparisonPhotoID = nil
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
        photoRatings = [:]
        currentPhotoIndex = 0
        groups = []
        sharpnessScores = [:]
        qualitySignalsByPhotoID = [:]
        activeFilter = .all
        comparisonEnabled = false
        comparisonPhotoID = nil
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
        photoRatings = [:]
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
        activeFilter = .all
        comparisonEnabled = false
        comparisonPhotoID = nil
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
