import Foundation

struct PhotoGroup: Identifiable {
    let id: UUID
    let number: Int
    let photos: [Photo]
    let startDate: Date?
    let endDate: Date?
    var isCollapsed: Bool = false
    var clusters: [[Photo]]? = nil

    var label: String {
        guard let start = startDate else {
            return photos.count == 1 ? photos[0].displayName : "Undated · \(photos.count) photos"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let end = endDate ?? start
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return formatter.string(from: start)
        }
        return formatter.string(from: start)
    }

    var momentTitle: String {
        "Moment \(number)"
    }
}
