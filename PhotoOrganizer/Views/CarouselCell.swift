import SwiftUI

struct CarouselCell: View {
    let photo: Photo
    let isActive: Bool
    let isSelected: Bool
    let sharpnessScore: Float?

    @State private var thumbnail: NSImage?

    private let size: CGFloat = 80

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail — explicit frame required so .fill image can't escape the cell
            ZStack {
                Color(white: 0.12)

                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            // Winner badge
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white, .green)
                    .padding(3)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }

            if let score = sharpnessScore {
                Circle()
                    .fill(score > 0.05 ? Color.green : (score > 0.02 ? Color.yellow : Color.red))
                    .frame(width: 7, height: 7)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(
                    isActive ? Color.white : (isSelected ? Color.green.opacity(0.8) : Color.clear),
                    lineWidth: isActive ? 2.5 : 1.5
                )
        )
        .scaleEffect(isActive ? 1.0 : 0.88)
        .animation(.easeInOut(duration: 0.12), value: isActive)
        .task(id: photo.id) {
            thumbnail = await ThumbnailService.shared.thumbnail(for: photo.thumbnailSourceURL, maxPixelSize: 256)
        }
    }
}
