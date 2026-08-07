import SwiftUI

/// Cold-start splash: the bolt draws itself, the sky flashes, the wordmark lands.
/// Tapping skips it — nobody wants a mandatory animation the second time.
struct BootAnimationView: View {
    var onFinished: () -> Void

    @Environment(\.stormTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var strokeProgress: Double = 0
    @State private var flashOpacity: Double = 0
    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkOffset: CGFloat = 12
    @State private var finished = false

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            RadialGradient(
                colors: [theme.accent.opacity(0.22 * strokeProgress), .clear],
                center: .center,
                startRadius: 8,
                endRadius: 320
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                GlowingBolt(progress: strokeProgress, charge: 0.9)
                    .frame(width: 92, height: 148)

                Text(verbatim: "StrikeShot")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
                    .opacity(wordmarkOpacity)
                    .offset(y: wordmarkOffset)
            }

            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task { await run() }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "StrikeShot"))
        .accessibilityAddTraits(.isImage)
    }

    private func run() async {
        guard !reduceMotion else {
            strokeProgress = 1
            wordmarkOpacity = 1
            wordmarkOffset = 0
            try? await Task.sleep(for: .milliseconds(400))
            finish()
            return
        }

        withAnimation(.easeOut(duration: 0.55)) { strokeProgress = 1 }
        try? await Task.sleep(for: .milliseconds(520))

        // Two-stage flash: the real thing has a leader and a return stroke.
        withAnimation(.easeOut(duration: 0.05)) { flashOpacity = 0.55 }
        try? await Task.sleep(for: .milliseconds(60))
        withAnimation(.easeIn(duration: 0.18)) { flashOpacity = 0 }
        try? await Task.sleep(for: .milliseconds(90))
        withAnimation(.easeOut(duration: 0.04)) { flashOpacity = 0.28 }
        try? await Task.sleep(for: .milliseconds(50))
        withAnimation(.easeIn(duration: 0.3)) { flashOpacity = 0 }

        withAnimation(.spring(duration: 0.5)) {
            wordmarkOpacity = 1
            wordmarkOffset = 0
        }
        try? await Task.sleep(for: .milliseconds(700))
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }
}
