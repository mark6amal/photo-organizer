import SwiftUI

struct LoupePanelView: View {
    let image: NSImage?
    let center: CGPoint
    @Binding var zoom: Int
    let locked: Bool

    var body: some View {
        VStack(spacing: 0) {
            Canvas { context, size in
                guard
                    let image,
                    let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                else {
                    return
                }

                let imageWidth = CGFloat(cgImage.width)
                let imageHeight = CGFloat(cgImage.height)
                let cropWidth = max(1, imageWidth / CGFloat(zoom))
                let cropHeight = max(1, imageHeight / CGFloat(zoom))

                let cropX = clamp(center.x * imageWidth - cropWidth / 2, to: 0...(imageWidth - cropWidth))
                let cropY = clamp((1 - center.y) * imageHeight - cropHeight / 2, to: 0...(imageHeight - cropHeight))

                if let crop = cgImage.cropping(
                    to: CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
                ) {
                    context.draw(
                        Image(nsImage: NSImage(cgImage: crop, size: size)),
                        in: CGRect(origin: .zero, size: size)
                    )
                }

                let midX = size.width / 2
                let midY = size.height / 2

                var horizontal = Path()
                horizontal.move(to: CGPoint(x: 0, y: midY))
                horizontal.addLine(to: CGPoint(x: size.width, y: midY))

                var vertical = Path()
                vertical.move(to: CGPoint(x: midX, y: 0))
                vertical.addLine(to: CGPoint(x: midX, y: size.height))

                context.stroke(horizontal, with: .color(.white.opacity(0.35)), lineWidth: 0.5)
                context.stroke(vertical, with: .color(.white.opacity(0.35)), lineWidth: 0.5)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(Color.black)
            .overlay(alignment: .topTrailing) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                        .padding(4)
                }
            }

            Picker("", selection: $zoom) {
                Text("5x").tag(5)
                Text("10x").tag(10)
                Text("20x").tag(20)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
        }
        .focusEffectDisabled()
        .background(Color(white: 0.06))
    }
}

private func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
    min(max(value, range.lowerBound), range.upperBound)
}
