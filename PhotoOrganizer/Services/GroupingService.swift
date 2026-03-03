import Foundation

enum GroupingService {
    static func group(photos: [Photo], gapThreshold: TimeInterval = 5) async -> [PhotoGroup] {
        await Task.detached(priority: .userInitiated) {
            let dated: [(photo: Photo, date: Date?)] = photos.map {
                ($0, EXIFService.captureDate(for: $0.thumbnailSourceURL))
            }

            let withDate = dated.filter { $0.date != nil }.sorted { $0.date! < $1.date! }
            let noDate   = dated.filter { $0.date == nil }

            var groups: [PhotoGroup] = []
            var bucket: [(photo: Photo, date: Date?)] = []

            for item in withDate {
                if let prev = bucket.last, let prevDate = prev.date, let thisDate = item.date,
                   thisDate.timeIntervalSince(prevDate) > gapThreshold {
                    groups.append(makeGroup(number: groups.count + 1, items: bucket))
                    bucket = [item]
                } else {
                    bucket.append(item)
                }
            }
            if !bucket.isEmpty { groups.append(makeGroup(number: groups.count + 1, items: bucket)) }

            if !noDate.isEmpty {
                groups.append(makeGroup(number: groups.count + 1, items: noDate))
            }

            return groups
        }.value
    }

    private static func makeGroup(number: Int, items: [(photo: Photo, date: Date?)]) -> PhotoGroup {
        PhotoGroup(
            id: UUID(),
            number: number,
            photos: items.map(\.photo),
            startDate: items.compactMap(\.date).first,
            endDate: items.compactMap(\.date).last
        )
    }
}
