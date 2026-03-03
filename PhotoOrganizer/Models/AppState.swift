import Foundation

@MainActor
@Observable
final class AppState {

    enum ViewMode { case filmstrip, grid }

    // MARK: - State

    var sourceURL: URL?
    var photos: [Photo] = []
    var selectedIDs: Set<UUID> = []
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

    // Histogram
    var histogramEnabled: Bool = false

    // Loupe
    var loupeEnabled: Bool = false

    // Metadata panel
    var metadataEnabled: Bool = false

    // Similarity metrics
    var sharpnessScores: [UUID: Float] = [:]

    // MARK: - Derived

    var currentPhoto: Photo? {
        photos.indices.contains(currentPhotoIndex) ? photos[currentPhotoIndex] : nil
    }
    var selectedPhotos: [Photo] { photos.filter { selectedIDs.contains($0.id) } }
    var hasSelection: Bool { !selectedIDs.isEmpty }
    var selectionCount: Int { selectedIDs.count }

    var currentGroupIndex: Int? {
        guard groupingEnabled, let current = currentPhoto else { return nil }
        return groups.firstIndex { $0.photos.contains { $0.id == current.id } }
    }

    var currentPhotoIndexInGroup: Int? {
        guard let gi = currentGroupIndex, let current = currentPhoto else { return nil }
        return groups[gi].photos.firstIndex { $0.id == current.id }.map { $0 + 1 }
    }

    var currentGroupPhotoCount: Int? {
        guard let gi = currentGroupIndex else { return nil }
        return groups[gi].photos.count
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
        if groupingEnabled,
           let gi = currentGroupIndex,
           let pos = currentPhotoIndexInGroup,
           let total = currentGroupPhotoCount {
            return "Group \(gi + 1) of \(groups.count) · Photo \(pos)/\(total)"
        }
        return "\(currentPhotoIndex + 1) / \(photos.count)"
    }

    func isSelected(_ photo: Photo) -> Bool { selectedIDs.contains(photo.id) }

    func selectedInGroup(_ group: PhotoGroup) -> Int {
        group.photos.filter { selectedIDs.contains($0.id) }.count
    }

    // MARK: - Selection

    func toggleSelected(_ photo: Photo) {
        if selectedIDs.contains(photo.id) {
            selectedIDs.remove(photo.id)
        } else {
            selectedIDs.insert(photo.id)
        }
    }

    func toggleCurrentPhoto() {
        guard let photo = currentPhoto else { return }
        toggleSelected(photo)
    }

    // MARK: - Navigation

    func navigateFilmstrip(by delta: Int) {
        guard !photos.isEmpty else { return }
        currentPhotoIndex = max(0, min(photos.count - 1, currentPhotoIndex + delta))
    }

    func navigateGroup(by delta: Int) {
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

    // MARK: - Grouping

    func computeGroups() async {
        guard groupingEnabled, !photos.isEmpty else {
            groups = []
            return
        }
        isGrouping = true
        groups = await GroupingService.group(photos: photos, gapThreshold: groupGapThreshold)
        isGrouping = false
        if similarityEnabled { await computeSimilarity() }
    }

    // MARK: - Visual Similarity

    func computeSimilarity() async {
        guard similarityEnabled, !groups.isEmpty else {
            for i in 0..<groups.count { groups[i].clusters = nil }
            sharpnessScores = [:]
            return
        }
        isSimilarityComputing = true
        sharpnessScores = [:]
        for i in 0..<groups.count {
            groups[i].clusters = await PixelSimilarityService.shared.cluster(
                photos: groups[i].photos,
                threshold: similarityThreshold
            )
            for photo in groups[i].photos {
                if let score = await PixelSimilarityService.shared.sharpness(for: photo.thumbnailSourceURL) {
                    sharpnessScores[photo.id] = score
                }
            }
        }
        isSimilarityComputing = false
    }

    func toggleGroupCollapsed(_ group: PhotoGroup) {
        guard let i = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[i].isCollapsed.toggle()
    }

    // MARK: - Rounds

    func startNewRound() {
        guard hasSelection else { return }
        let round = SelectionRound(
            id: UUID(),
            number: rounds.count + 1,
            sourcePhotos: photos,
            selectedIDs: selectedIDs,
            date: Date()
        )
        rounds.append(round)
        photos = round.winners
        selectedIDs = []
        currentPhotoIndex = 0
        SessionStore.save(self)
    }

    // MARK: - Loading

    func loadPhotos(from url: URL) async {
        isScanning = true
        scanError = nil
        photos = []
        selectedIDs = []
        currentPhotoIndex = 0
        do {
            photos = try await FolderScanner.scan(url: url)
        } catch {
            scanError = error.localizedDescription
        }
        isScanning = false
        RecentFolders.add(url)
        SessionStore.save(self)
    }

    func reset() {
        sourceURL = nil
        photos = []
        selectedIDs = []
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
        SessionStore.clear()
    }
}
