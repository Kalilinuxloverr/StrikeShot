import AVFoundation
import SwiftUI
import UIKit

/// Full-screen capture cockpit: viewfinder, arm switch, live luma, results strip.
struct CaptureScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.stormTheme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var pulsing = false

    var body: some View {
        let capture = services.capture
        ZStack {
            backgroundLayer
            VStack(spacing: 12) {
                if let message = capture.lastError {
                    errorBanner(message)
                }
                if capture.permission == .unavailable, capture.isRunning {
                    simulationChip
                }
                Spacer(minLength: 0)
                switch capture.permission {
                case .denied:
                    deniedCard
                case .unavailable where !capture.isRunning:
                    unavailableCard
                default:
                    EmptyView()
                }
                Spacer(minLength: 0)
                if capture.permission == .authorized || capture.isRunning {
                    armButton
                    controlPanel
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .task { await services.capture.start() }
        .onDisappear {
            if services.capture.isArmed {
                services.endStormSession()
            }
            services.capture.stop()
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        if services.capture.permission == .authorized {
            CameraPreview(session: services.capture.session)
                .ignoresSafeArea()
        } else {
            theme.background.ignoresSafeArea()
            if services.capture.isRunning {
                // Simulated sky: the synthetic luma flashes the whole backdrop.
                theme.accentGlow
                    .opacity(services.capture.currentLuma * 0.5)
                    .ignoresSafeArea()
                    .animation(.linear(duration: 0.05), value: services.capture.currentLuma)
            }
        }
    }

    // MARK: - Banners and empty states

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.danger)
            Text(message)
                .font(.footnote)
                .foregroundStyle(theme.primaryText)
            Spacer(minLength: 0)
            Button {
                services.capture.lastError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.bold())
                    .foregroundStyle(theme.secondaryText)
            }
            .accessibilityLabel(String(localized: "capture.error.dismiss", defaultValue: "Fehlermeldung schließen"))
        }
        .padding(12)
        .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.danger.opacity(0.6), lineWidth: 1))
    }

    private var simulationChip: some View {
        Label(String(localized: "capture.simulation.active", defaultValue: "Simulationsmodus"),
              systemImage: "wand.and.stars")
            .font(.caption.bold())
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(theme.surface.opacity(0.9), in: Capsule())
    }

    private var deniedCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 42))
                .foregroundStyle(theme.secondaryText)
            Text(String(localized: "capture.denied.title", defaultValue: "Kein Kamerazugriff"))
                .font(.title3.bold())
                .foregroundStyle(theme.primaryText)
            Text(String(localized: "capture.denied.message",
                        defaultValue: "Erlaube StrikeShot den Kamerazugriff in den Einstellungen, um Blitze automatisch aufzunehmen."))
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text(String(localized: "capture.denied.settings", defaultValue: "Einstellungen öffnen"))
                    .font(.body.bold())
                    .foregroundStyle(theme.background)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(theme.accent, in: Capsule())
            }
        }
        .padding(24)
        .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 24))
    }

    private var unavailableCard: some View {
        VStack(spacing: 14) {
            GlowingBolt(charge: 0.6)
                .frame(width: 34, height: 48)
            Text(String(localized: "capture.unavailable.title", defaultValue: "Keine Kamera verfügbar"))
                .font(.title3.bold())
                .foregroundStyle(theme.primaryText)
            Text(String(localized: "capture.unavailable.message",
                        defaultValue: "Im iOS-Simulator gibt es keine Kamera. Die Blitz-Simulation erzeugt synthetische Blitze, Trigger und Platzhalter-Aufnahmen."))
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                services.capture.startSimulation()
            } label: {
                Text(String(localized: "capture.unavailable.start", defaultValue: "Simulation starten"))
                    .font(.body.bold())
                    .foregroundStyle(theme.background)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(theme.accent, in: Capsule())
            }
        }
        .padding(24)
        .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Arm button

    private var armButton: some View {
        let capture = services.capture
        return Button {
            if capture.isArmed {
                capture.disarm()
                services.endStormSession()
            } else {
                capture.arm()
                services.beginStormSession()
            }
        } label: {
            ZStack {
                Circle().fill(theme.surfaceRaised)
                Circle().stroke(capture.isArmed ? theme.accent : theme.secondaryText.opacity(0.35), lineWidth: 2.5)
                GlowingBolt(charge: capture.isArmed ? 1 : 0.3)
                    .frame(width: 30, height: 42)
            }
            .frame(width: 86, height: 86)
            .scaleEffect(capture.isArmed && pulsing ? 1.06 : 1)
            .shadow(color: theme.accentGlow.opacity(capture.isArmed ? 0.7 : 0),
                    radius: pulsing ? theme.glowRadius + 10 : 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "capture.arm.a11y", defaultValue: "Automatischer Blitz-Auslöser"))
        .accessibilityValue(capture.isArmed
            ? String(localized: "capture.arm.on", defaultValue: "Scharf")
            : String(localized: "capture.arm.off", defaultValue: "Aus"))
        .accessibilityHint(String(localized: "capture.arm.hint",
                                  defaultValue: "Löst bei erkannten Blitzen automatisch aus."))
        .onChange(of: capture.isArmed) { _, armed in
            if armed {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.25)) {
                    pulsing = false
                }
            }
        }
    }

    // MARK: - Control panel

    private var controlPanel: some View {
        @Bindable var capture = services.capture
        @Bindable var settings = services.settings
        return VStack(spacing: 14) {
            if !capture.recentCaptures.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(capture.recentCaptures) { result in
                            CaptureThumbnail(result: result)
                        }
                    }
                }
            }

            LumaBar(luma: capture.currentLuma, baseline: capture.baselineLuma)

            HStack(spacing: 16) {
                Label("\(capture.triggerCount)", systemImage: "bolt.fill")
                    .font(.callout.bold())
                    .foregroundStyle(theme.accent)
                    .accessibilityLabel(String(localized: "capture.triggerCount.a11y", defaultValue: "Ausgelöste Blitze"))
                    .accessibilityValue("\(capture.triggerCount)")
                if let meters = capture.lastThunderDistanceMeters {
                    Label(meters.formattedDistance, systemImage: "waveform")
                        .font(.callout)
                        .foregroundStyle(theme.primaryText)
                        .accessibilityLabel(String(localized: "capture.thunder.a11y", defaultValue: "Donner-Entfernung"))
                        .accessibilityValue(meters.formattedDistance)
                }
                Spacer()
                Button {
                    capture.manualTrigger()
                } label: {
                    Image(systemName: "camera.shutter.button")
                        .font(.title3)
                        .foregroundStyle(theme.primaryText)
                }
                .accessibilityLabel(String(localized: "capture.manual", defaultValue: "Manuell auslösen"))
            }

            Picker(String(localized: "capture.mode.title", defaultValue: "Modus"), selection: $capture.mode) {
                ForEach(CaptureMode.allCases) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(localized: "capture.sensitivity", defaultValue: "Empfindlichkeit"))
                    Spacer()
                    Text(settings.triggerSensitivity, format: .percent.precision(.fractionLength(0)))
                }
                .font(.footnote)
                .foregroundStyle(theme.secondaryText)
                Slider(value: $settings.triggerSensitivity, in: 0...1)
                    .tint(theme.accent)
                    .accessibilityLabel(String(localized: "capture.sensitivity", defaultValue: "Empfindlichkeit"))
            }
        }
        .padding(16)
        .background(theme.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 24))
    }
}

/// Live luma bar with a marker at the detector baseline.
private struct LumaBar: View {
    let luma: Double
    let baseline: Double
    @Environment(\.stormTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.background.opacity(0.8))
                Capsule()
                    .fill(LinearGradient(colors: [theme.accent, theme.accentGlow],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, geometry.size.width * luma))
                Rectangle()
                    .fill(theme.primaryText.opacity(0.85))
                    .frame(width: 2)
                    .offset(x: geometry.size.width * baseline)
            }
        }
        .frame(height: 10)
        .animation(.linear(duration: 0.1), value: luma)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "capture.luma.a11y", defaultValue: "Helligkeit"))
        .accessibilityValue(String(localized: "capture.luma.value",
                                   defaultValue: "\(Int(luma * 100)) Prozent, Grundpegel \(Int(baseline * 100)) Prozent"))
    }
}

private struct CaptureThumbnail: View {
    let result: CaptureResult
    @Environment(\.stormTheme) private var theme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let data = result.thumbnailData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.surfaceRaised)
                        .overlay(
                            Image(systemName: result.mode.symbolName)
                                .foregroundStyle(theme.secondaryText)
                        )
                }
            }
            .frame(width: 72, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 3) {
                Image(systemName: result.mode.symbolName)
                    .font(.system(size: 9))
                if let meters = result.thunderDistanceMeters {
                    Text(meters.formattedDistance)
                        .font(.system(size: 9))
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(theme.background.opacity(0.65), in: Capsule())
            .foregroundStyle(theme.primaryText)
            .padding(3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.mode.localizedName)
        .accessibilityValue(result.thunderDistanceMeters.map(\.formattedDistance) ?? "")
    }
}
