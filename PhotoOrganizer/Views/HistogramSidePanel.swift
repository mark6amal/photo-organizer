import SwiftUI

struct HistogramSidePanel: View {
    let photo: Photo

    @State private var histData: HistogramData?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let data = histData {
                VStack(spacing: 8) {
                    HistogramChart(data: data)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                    HStack(spacing: 0) {
                        ForEach(["R", "G", "B", "L"], id: \.self) { label in
                            Text(label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(channelColor(label))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .focusEffectDisabled()
        .frame(width: 200)
        .background(Color(white: 0.06))
        .task(id: photo.id) {
            isLoading = true
            histData = nil
            histData = await HistogramService.shared.histogram(for: photo.thumbnailSourceURL)
            isLoading = false
        }
    }

    private func channelColor(_ label: String) -> Color {
        switch label {
        case "R": return .red.opacity(0.8)
        case "G": return .green.opacity(0.8)
        case "B": return .blue.opacity(0.8)
        default: return .white.opacity(0.6)
        }
    }
}
