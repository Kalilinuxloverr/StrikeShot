import SwiftUI

/// The StrikeShot bolt. Drawn rather than an asset so it can be stroke-animated.
struct BoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Normalised bolt, traced top-down so `.trim` reads as "drawing a strike".
        let points: [CGPoint] = [
            CGPoint(x: 0.62, y: 0.00),
            CGPoint(x: 0.24, y: 0.52),
            CGPoint(x: 0.47, y: 0.52),
            CGPoint(x: 0.34, y: 1.00),
            CGPoint(x: 0.78, y: 0.40),
            CGPoint(x: 0.53, y: 0.40),
            CGPoint(x: 0.72, y: 0.00),
        ]
        var path = Path()
        for (index, point) in points.enumerated() {
            let scaled = CGPoint(x: rect.minX + point.x * rect.width,
                                 y: rect.minY + point.y * rect.height)
            if index == 0 { path.move(to: scaled) } else { path.addLine(to: scaled) }
        }
        path.closeSubpath()
        return path
    }
}

/// A bolt that can glow and pulse with the current theme charge.
struct GlowingBolt: View {
    var progress: Double = 1
    var charge: Double = 1
    @Environment(\.stormTheme) private var theme

    var body: some View {
        ZStack {
            BoltShape()
                .trim(from: 0, to: progress)
                .stroke(theme.accentGlow,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .blur(radius: 8 * charge + 2)
            BoltShape()
                .trim(from: 0, to: progress)
                .stroke(theme.accent,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            BoltShape()
                .fill(theme.accent.opacity(0.18 + 0.35 * charge * progress))
        }
    }
}
