import Foundation

// MARK: - Session Persistence

@MainActor
enum SessionStore {
    private static var sessionURL: URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = support.appending(component: "PhotoOrganizer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(component: "session.json")
    }

    static func save(_ state: AppState) {
        guard let url = sessionURL else { return }
        let decisions = state.photoDecisions.map { StoredDecision(id: $0.key, state: $0.value) }
        let ratings = state.photoRatings.map { StoredRating(id: $0.key, rating: $0.value) }
        let data = SessionData(
            sourceURL: state.sourceURL,
            photos: state.photos,
            decisions: decisions,
            ratings: ratings,
            legacySelectedIDs: Array(state.selectedIDs),
            rounds: state.rounds,
            viewMode: state.viewMode == .filmstrip ? "filmstrip" : "grid"
        )
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: url)
    }

    static func restore(into state: AppState) {
        guard
            let url = sessionURL,
            let data = try? Data(contentsOf: url),
            let session = try? JSONDecoder().decode(SessionData.self, from: data)
        else { return }

        let fm = FileManager.default
        let validPhotos = session.photos.filter { fm.fileExists(atPath: $0.url.path) }
        guard !validPhotos.isEmpty else { return }

        let validIDs = Set(validPhotos.map(\.id))
        state.sourceURL = session.sourceURL
        state.photos = validPhotos
        state.photoDecisions = session.restoredDecisions(validIDs: validIDs)
        state.photoRatings = session.restoredRatings(validIDs: validIDs)
        state.rounds = session.rounds
        state.viewMode = session.viewMode == "grid" ? .grid : .filmstrip
        state.currentPhotoIndex = 0
    }

    static func clear() {
        guard let url = sessionURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

private struct StoredDecision: Codable {
    let id: UUID
    let state: DecisionState
}

private struct StoredRating: Codable {
    let id: UUID
    let rating: Int
}

private struct SessionData: Codable {
    let sourceURL: URL?
    let photos: [Photo]
    let decisions: [StoredDecision]
    let ratings: [StoredRating]
    let legacySelectedIDs: [UUID]
    let rounds: [SelectionRound]
    let viewMode: String

    init(
        sourceURL: URL?,
        photos: [Photo],
        decisions: [StoredDecision],
        ratings: [StoredRating],
        legacySelectedIDs: [UUID],
        rounds: [SelectionRound],
        viewMode: String
    ) {
        self.sourceURL = sourceURL
        self.photos = photos
        self.decisions = decisions
        self.ratings = ratings
        self.legacySelectedIDs = legacySelectedIDs
        self.rounds = rounds
        self.viewMode = viewMode
    }

    private enum CodingKeys: String, CodingKey {
        case sourceURL
        case photos
        case decisions
        case ratings
        case legacySelectedIDs = "selectedIDs"
        case rounds
        case viewMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
        photos = try container.decode([Photo].self, forKey: .photos)
        decisions = try container.decodeIfPresent([StoredDecision].self, forKey: .decisions) ?? []
        ratings = try container.decodeIfPresent([StoredRating].self, forKey: .ratings) ?? []
        legacySelectedIDs = try container.decodeIfPresent([UUID].self, forKey: .legacySelectedIDs) ?? []
        rounds = try container.decodeIfPresent([SelectionRound].self, forKey: .rounds) ?? []
        viewMode = try container.decodeIfPresent(String.self, forKey: .viewMode) ?? "filmstrip"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encode(photos, forKey: .photos)
        try container.encode(decisions, forKey: .decisions)
        try container.encode(ratings, forKey: .ratings)
        try container.encode(legacySelectedIDs, forKey: .legacySelectedIDs)
        try container.encode(rounds, forKey: .rounds)
        try container.encode(viewMode, forKey: .viewMode)
    }

    func restoredDecisions(validIDs: Set<UUID>) -> [UUID: DecisionState] {
        if !decisions.isEmpty {
            return decisions.reduce(into: [UUID: DecisionState]()) { partial, entry in
                guard validIDs.contains(entry.id) else { return }
                partial[entry.id] = entry.state
            }
        }

        return legacySelectedIDs.reduce(into: [UUID: DecisionState]()) { partial, id in
            guard validIDs.contains(id) else { return }
            partial[id] = .kept
        }
    }

    func restoredRatings(validIDs: Set<UUID>) -> [UUID: Int] {
        ratings.reduce(into: [UUID: Int]()) { partial, entry in
            guard validIDs.contains(entry.id) else { return }
            partial[entry.id] = entry.rating
        }
    }
}

// MARK: - Recent Folders

enum RecentFolders {
    private static let key = "recentFolderURLs"

    static func all() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        return paths
            .compactMap { URL(string: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func add(_ url: URL) {
        var list = all().map(\.absoluteString)
        list.removeAll { $0 == url.absoluteString }
        list.insert(url.absoluteString, at: 0)
        UserDefaults.standard.set(Array(list.prefix(8)), forKey: key)
    }
}
