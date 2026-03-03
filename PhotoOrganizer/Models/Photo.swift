import Foundation

let rawExtensions: Set<String> = ["cr2", "cr3", "nef", "arw", "dng", "raf", "rw2", "orf"]
let jpegExtensions: Set<String> = ["jpg", "jpeg"]

struct Photo: Identifiable, Sendable, Codable {
    let id: UUID
    let url: URL
    let jpegPairURL: URL?

    var displayName: String { url.deletingPathExtension().lastPathComponent }
    var isRAW: Bool { rawExtensions.contains(url.pathExtension.lowercased()) }
    var thumbnailSourceURL: URL { jpegPairURL ?? url }

    init(url: URL, jpegPairURL: URL? = nil) {
        self.id = UUID()
        self.url = url
        self.jpegPairURL = jpegPairURL
    }
}
