import SwiftUI

struct MetadataSidePanel: View {
    @Environment(AppState.self) private var appState
    let photo: Photo

    @State private var meta: EXIFMetadata?
    @State private var isLoading = true

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isLoading {
                    ProgressView()
                        .padding()
                        .frame(maxWidth: .infinity)
                } else if let meta {
                    rows(for: meta, photo: photo)
                }
            }
            .padding(.vertical, 12)
        }
        .focusEffectDisabled()
        .frame(width: 200)
        .background(Color(white: 0.06))
        .task(id: photo.id) {
            isLoading = true
            meta = nil
            let url = photo.thumbnailSourceURL
            let result = await Task.detached { EXIFService.metadata(for: url) }.value
            meta = result
            await appState.ensureQualitySignals(for: photo)
            isLoading = false
        }
    }

    @ViewBuilder
    private func rows(for meta: EXIFMetadata, photo: Photo) -> some View {
        row(label: "Decision", value: decisionLabel(for: photo))
        row(label: "Format", value: formatString(photo))
        if photo.isRAW, let jpegURL = photo.jpegPairURL {
            row(label: "Paired JPEG", value: jpegURL.lastPathComponent)
        }
        if let signals = appState.qualitySignals(for: photo) {
            row(label: "Sharpness", value: signals.sharpnessLabel)
            row(label: "Exposure", value: signals.exposureLabel)
            row(label: "Recovery", value: signals.recoverabilityHint)
        } else if let score = appState.sharpnessScores[photo.id] {
            row(label: "Sharpness", value: sharpnessLabel(score))
        }

        if let make = meta.cameraMake { row(label: "Camera", value: make) }
        if let model = meta.cameraModel { row(label: "Model", value: model) }
        if let lens = meta.lensModel { row(label: "Lens", value: lens) }
        if let aperture = meta.aperture { row(label: "Aperture", value: aperture) }
        if let shutter = meta.shutterSpeed { row(label: "Shutter", value: shutter) }
        if let iso = meta.iso { row(label: "ISO", value: iso) }
        if let fl = meta.focalLength { row(label: "Focal Length", value: fl) }
        if let date = meta.captureDate { row(label: "Date", value: dateFormatter.string(from: date)) }
        row(label: "Filename", value: photo.url.lastPathComponent)
    }

    private func row(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.35))
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
                .background(.white.opacity(0.08))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func formatString(_ photo: Photo) -> String {
        let ext = photo.url.pathExtension.uppercased()
        if photo.isRAW {
            return photo.jpegPairURL != nil ? "RAW + JPEG (\(ext))" : "RAW (\(ext))"
        }
        return "JPEG"
    }

    private func sharpnessLabel(_ value: Float) -> String {
        let score = Int(value * 1000)
        switch value {
        case ..<0.03:
            return "Low (\(score))"
        case ..<0.1:
            return "Medium (\(score))"
        default:
            return "High (\(score))"
        }
    }

    private func decisionLabel(for photo: Photo) -> String {
        switch appState.decisionState(for: photo) {
        case .kept:
            return "Kept"
        case .rejected:
            return "Rejected"
        case .undecided:
            return "Undecided"
        }
    }
}
