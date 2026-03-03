import SwiftUI

// MARK: - Mini-bar (grid cells)

struct HistogramMiniBar: View {
    let data: HistogramData

    var body: some View {
        Canvas { ctx, size in
            let n = data.luma.count
            let w = size.width / CGFloat(n)
            for i in 0..<n {
                let h = CGFloat(data.luma[i]) * size.height
                let rect = CGRect(x: CGFloat(i) * w, y: size.height - h, width: w + 0.5, height: h)
                ctx.fill(Path(rect), with: .color(.white.opacity(0.75)))
            }
        }
        .frame(height: 20)
        .background(.black.opacity(0.5))
    }
}

// MARK: - Full chart (filmstrip overlay)

struct HistogramChart: View {
    let data: HistogramData

    var body: some View {
        Canvas { ctx, size in
            drawFilled(data.blue,  color: .blue,  ctx: ctx, size: size)
            drawFilled(data.green, color: .green, ctx: ctx, size: size)
            drawFilled(data.red,   color: .red,   ctx: ctx, size: size)
            drawLine(data.luma,    color: .white,  ctx: ctx, size: size)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func drawFilled(_ bins: [Float], color: Color, ctx: GraphicsContext, size: CGSize) {
        let n = bins.count
        guard n > 1 else { return }
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for i in 0..<n {
            let x = CGFloat(i) / CGFloat(n - 1) * size.width
            let y = size.height - CGFloat(bins[i]) * size.height
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        ctx.fill(path, with: .color(color.opacity(0.22)))
        ctx.stroke(path, with: .color(color.opacity(0.55)), lineWidth: 1)
    }

    private func drawLine(_ bins: [Float], color: Color, ctx: GraphicsContext, size: CGSize) {
        let n = bins.count
        guard n > 1 else { return }
        var path = Path()
        for i in 0..<n {
            let x = CGFloat(i) / CGFloat(n - 1) * size.width
            let y = size.height - CGFloat(bins[i]) * size.height
            i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        ctx.stroke(path, with: .color(color.opacity(0.85)), lineWidth: 1)
    }
}
