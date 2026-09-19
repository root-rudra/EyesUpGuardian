import SwiftUI

/// A tiny history chart. Draws nothing when there's no history yet, so it never implies data it lacks.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = .orange

    var body: some View {
        GeometryReader { geometry in
            if values.count > 1 {
                let highest = max(values.max() ?? 1, 0.0001)
                let step = geometry.size.width / CGFloat(values.count - 1)
                let points = values.enumerated().map { index, value in
                    CGPoint(
                        x: CGFloat(index) * step,
                        y: geometry.size.height * (1 - CGFloat(min(max(value / highest, 0), 1)))
                    )
                }
                Path { path in
                    path.move(to: points[0])
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height))
                    for point in points { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .frame(height: 32)
        .accessibilityHidden(true)
    }
}
