import Foundation

struct SelectionRound: Identifiable, Codable {
    let id: UUID
    let number: Int
    let sourcePhotos: [Photo]
    let selectedIDs: Set<UUID>
    let date: Date

    var winners: [Photo] { sourcePhotos.filter { selectedIDs.contains($0.id) } }
    var winnerCount: Int { selectedIDs.count }
}
