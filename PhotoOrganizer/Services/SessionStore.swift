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
        let data = SessionData(
            sourceURL: state.sourceURL,
            photos: state.photos,
            selectedIDs: Array(state.selectedIDs),
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
        state.selectedIDs = Set(session.selectedIDs).intersection(validIDs)
        state.rounds = session.rounds
        state.viewMode = session.viewMode == "grid" ? .grid : .filmstrip
        state.currentPhotoIndex = 0
    }

    static func clear() {
        guard let url = sessionURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

private struct SessionData: Codable {
    let sourceURL: URL?
    let photos: [Photo]
    let selectedIDs: [UUID]
    let rounds: [SelectionRound]
    let viewMode: String
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
