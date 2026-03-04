import SwiftUI

struct ThumbnailCell: View {
    let photo: Photo
    let size: CGFloat
    let decisionState: DecisionState
    let isFocused: Bool
    var showHistogram: Bool = false
    var qualitySignals: PhotoQualitySignals? = nil

    @State private var thumbnail: NSImage?
    @State private var histData: HistogramData?

    private struct HistTaskID: Equatable {
        let photoID: UUID
        let show: Bool
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
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

                decisionOverlay
            }

            decisionBadge
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                if showHistogram, let hist = histData {
                    HistogramMiniBar(data: hist)
                }
                if let qualitySignals {
                    qualityBadgeRow(signals: qualitySignals)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    borderColor,
                    lineWidth: decisionState == .undecided ? 2 : 2.5
                )
        )
        .task(id: photo.id) {
            let pixelSize = max(192, min(512, Int(size * 2)))
            thumbnail = await ThumbnailService.shared.thumbnail(
                for: photo.thumbnailSourceURL,
                maxPixelSize: pixelSize
            )
        }
        .task(id: HistTaskID(photoID: photo.id, show: showHistogram)) {
            guard showHistogram else {
                histData = nil
                return
            }
            histData = await HistogramService.shared.histogram(for: photo.thumbnailSourceURL)
        }
    }

    @ViewBuilder
    private var decisionOverlay: some View {
        switch decisionState {
        case .kept:
            Color.green.opacity(0.18)
        case .rejected:
            Color.red.opacity(0.2)
        case .undecided:
            EmptyView()
        }
    }

    @ViewBuilder
    private var decisionBadge: some View {
        switch decisionState {
        case .kept:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: max(16, size * 0.12)))
                .foregroundStyle(.white, .green)
                .shadow(radius: 2)
                .padding(6)
        case .rejected:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: max(16, size * 0.12)))
                .foregroundStyle(.white, .red)
                .shadow(radius: 2)
                .padding(6)
        case .undecided:
            EmptyView()
        }
    }

    private var borderColor: Color {
        switch decisionState {
        case .kept:
            return .green
        case .rejected:
            return .red.opacity(0.8)
        case .undecided:
            return isFocused ? .accentColor : .clear
        }
    }

    private func qualityBadgeRow(signals: PhotoQualitySignals) -> some View {
        HStack(spacing: 4) {
            Text(shortSharpnessLabel(signals))
            if signals.hasHighlightClipping || signals.hasShadowClipping {
                Text("EXP")
            }
        }
        .font(.system(size: max(8, size * 0.06), weight: .semibold))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.65))
    }

    private func shortSharpnessLabel(_ signals: PhotoQualitySignals) -> String {
        switch signals.sharpnessLabel {
        case "Sharp":
            return "SHARP"
        case "Borderline":
            return "OK"
        default:
            return "SOFT"
        }
    }
}
