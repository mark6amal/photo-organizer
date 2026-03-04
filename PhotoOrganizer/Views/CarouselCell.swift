import SwiftUI

struct CarouselCell: View {
    let photo: Photo
    let isActive: Bool
    let decisionState: DecisionState
    let qualitySignals: PhotoQualitySignals?

    @State private var thumbnail: NSImage?

    private let size: CGFloat = 80

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Color(white: 0.12)

                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }

                decisionOverlay
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            decisionBadge

            if let qualitySignals {
                qualityMarker(signals: qualitySignals)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(borderColor, lineWidth: isActive ? 2.5 : 1.5)
        )
        .scaleEffect(isActive ? 1.0 : 0.88)
        .animation(.easeInOut(duration: 0.12), value: isActive)
        .task(id: photo.id) {
            thumbnail = await ThumbnailService.shared.thumbnail(for: photo.thumbnailSourceURL, maxPixelSize: 256)
        }
    }

    @ViewBuilder
    private var decisionOverlay: some View {
        switch decisionState {
        case .kept:
            Color.green.opacity(0.15)
        case .rejected:
            Color.red.opacity(0.22)
        case .undecided:
            EmptyView()
        }
    }

    @ViewBuilder
    private var decisionBadge: some View {
        switch decisionState {
        case .kept:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white, .green)
                .padding(3)
                .shadow(color: .black.opacity(0.5), radius: 2)
        case .rejected:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white, .red)
                .padding(3)
                .shadow(color: .black.opacity(0.5), radius: 2)
        case .undecided:
            EmptyView()
        }
    }

    private var borderColor: Color {
        if isActive { return .white }
        switch decisionState {
        case .kept:
            return Color.green.opacity(0.85)
        case .rejected:
            return Color.red.opacity(0.85)
        case .undecided:
            return .clear
        }
    }

    private func qualityMarker(signals: PhotoQualitySignals) -> some View {
        Circle()
            .fill(signalColor(signals))
            .frame(width: 7, height: 7)
            .padding(4)
    }

    private func signalColor(_ signals: PhotoQualitySignals) -> Color {
        if signals.sharpnessLabel == "Sharp" && !signals.hasHighlightClipping && !signals.hasShadowClipping {
            return .green
        }
        if signals.sharpnessLabel == "Soft" || signals.hasHighlightClipping || signals.hasShadowClipping {
            return .red
        }
        return .yellow
    }
}
