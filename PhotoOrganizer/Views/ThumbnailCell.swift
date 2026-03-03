import SwiftUI

struct ThumbnailCell: View {
    let photo: Photo
    let size: CGFloat
    let isSelected: Bool
    let isFocused: Bool
    var showHistogram: Bool = false

    @State private var thumbnail: NSImage?
    @State private var histData: HistogramData?

    private struct HistTaskID: Equatable {
        let photoID: UUID; let show: Bool
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Base thumbnail
            ZStack {
                Color(NSColor.controlBackgroundColor)

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ProgressView()
                        .scaleEffect(0.5)
                }
            }

            // Winner overlay
            if isSelected {
                Color.green.opacity(0.18)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: max(16, size * 0.12)))
                    .foregroundStyle(.white, .green)
                    .shadow(radius: 2)
                    .padding(6)
            }
        }
        .overlay(alignment: .bottom) {
            if showHistogram, let hist = histData {
                HistogramMiniBar(data: hist)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isSelected ? Color.green : (isFocused ? Color.accentColor : Color.clear),
                    lineWidth: isSelected ? 2.5 : 2
                )
        )
        .task(id: photo.id) {
            thumbnail = await ThumbnailService.shared.thumbnail(for: photo.thumbnailSourceURL)
        }
        .task(id: HistTaskID(photoID: photo.id, show: showHistogram)) {
            guard showHistogram else { histData = nil; return }
            histData = await HistogramService.shared.histogram(for: photo.thumbnailSourceURL)
        }
    }
}
