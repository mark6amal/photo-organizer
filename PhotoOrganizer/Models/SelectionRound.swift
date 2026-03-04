import Foundation

struct SelectionRound: Identifiable, Codable {
    let id: UUID
    let number: Int
    let sourcePhotos: [Photo]
    let keptIDs: Set<UUID>
    let date: Date

    var winners: [Photo] { sourcePhotos.filter { keptIDs.contains($0.id) } }
    var winnerCount: Int { keptIDs.count }

    var selectedIDs: Set<UUID> { keptIDs }

    init(
        id: UUID,
        number: Int,
        sourcePhotos: [Photo],
        keptIDs: Set<UUID>,
        date: Date
    ) {
        self.id = id
        self.number = number
        self.sourcePhotos = sourcePhotos
        self.keptIDs = keptIDs
        self.date = date
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case number
        case sourcePhotos
        case keptIDs
        case selectedIDs
        case date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        number = try container.decode(Int.self, forKey: .number)
        sourcePhotos = try container.decode([Photo].self, forKey: .sourcePhotos)
        if let decodedKeptIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .keptIDs) {
            keptIDs = decodedKeptIDs
        } else if let legacySelectedIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .selectedIDs) {
            keptIDs = legacySelectedIDs
        } else {
            keptIDs = []
        }
        date = try container.decode(Date.self, forKey: .date)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(number, forKey: .number)
        try container.encode(sourcePhotos, forKey: .sourcePhotos)
        try container.encode(keptIDs, forKey: .keptIDs)
        try container.encode(date, forKey: .date)
    }
}
