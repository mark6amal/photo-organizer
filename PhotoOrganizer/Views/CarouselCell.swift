import SwiftUI

struct CarouselCell: View {
    let photo: Photo
    let isActive: Bool
    let isComparison: Bool
    let decisionState: DecisionState
    let starRating: Int
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

            if qualitySignals?.isBestPick == true {
                Image(systemName: "crown.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
                    .shadow(color: .black.opacity(0.8), radius: 2)
                    .padding(3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if let qualitySignals {
                qualityMarker(signals: qualitySignals)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

            if starRating > 0 {
                starRow(rating: starRating)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .scaleEffect(isActive ? 1.0 : (isComparison ? 0.94 : 0.88))
        .animation(.easeInOut(duration: 0.12), value: isActive)
        .animation(.easeInOut(duration: 0.12), value: isComparison)
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
        if isComparison { return .blue }
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

    private var borderWidth: CGFloat {
        if isActive || isComparison { return 2.5 }
        return decisionState == .undecided ? 0 : 1.5
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

    private func starRow(rating: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(1...min(rating, 5), id: \.self) { _ in
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 4, height: 4)
            }
        }
        .padding(4)
    }
}
