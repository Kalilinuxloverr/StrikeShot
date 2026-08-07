import AVFoundation
import Foundation

/// After a flash trigger, listens on the microphone for the thunder peak and
/// reports distance = delay × speed of sound. One ranging at a time; a new
/// flash restarts the clock.
@MainActor
final class ThunderRanger {
    enum Outcome {
        case distance(Double)
        case failed(String)
    }

    static let speedOfSoundMetersPerSecond = 343.0
    static let listeningWindow: TimeInterval = 90
    /// Skip the first moments after the flash: closer than ~170 m is not
    /// resolvable this way, and it keeps shutter/handling noise out.
    static let minimumDelay: TimeInterval = 0.5

    private(set) var isListening = false
    private var engine: AVAudioEngine?
    private var timeoutTask: Task<Void, Never>?

    /// No audible thunder within the window is a normal outcome and reports nothing.
    func beginRanging(flashAt flash: Date, completion: @escaping @MainActor (Outcome) -> Void) {
        cancel()
        isListening = true
        Task { [weak self] in
            let granted = await AVAudioApplication.requestRecordPermission()
            guard let self, self.isListening else { return }
            guard granted else {
                self.isListening = false
                completion(.failed(String(localized: "thunder.error.micDenied",
                                          defaultValue: "Ohne Mikrofonzugriff keine Donner-Entfernung.")))
                return
            }
            self.startEngine(flash: flash, completion: completion)
        }
    }

    func cancel() {
        finish()
    }

    private func startEngine(flash: Date, completion: @escaping @MainActor (Outcome) -> Void) {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            isListening = false
            completion(.failed(String(localized: "thunder.error.session",
                                      defaultValue: "Audio-Aufnahme nicht möglich: \(error.localizedDescription)")))
            return
        }

        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            finish()
            completion(.failed(String(localized: "thunder.error.noInput",
                                      defaultValue: "Kein Mikrofon verfügbar.")))
            return
        }

        // Tap state stays inside the closure; the tap is serial, so no locking.
        var noiseFloor = 0.02
        var fired = false
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard !fired, let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var sum = 0.0
            let samples = channels[0]
            for index in 0..<frames {
                let value = Double(samples[index])
                sum += value * value
            }
            let rms = sqrt(sum / Double(frames))
            let elapsed = Date().timeIntervalSince(flash)
            // Thunder = clear jump over the rolling ambient floor.
            if elapsed > Self.minimumDelay, rms > max(noiseFloor * 4, 0.02) {
                fired = true
                let distance = elapsed * Self.speedOfSoundMetersPerSecond
                Task { @MainActor [weak self] in
                    self?.finish()
                    completion(.distance(distance))
                }
            } else {
                // Slow EMA so a building rumble cannot raise its own floor.
                noiseFloor += (rms - noiseFloor) * 0.05
            }
        }

        do {
            try engine.start()
        } catch {
            finish()
            completion(.failed(String(localized: "thunder.error.engine",
                                      defaultValue: "Mikrofon konnte nicht gestartet werden: \(error.localizedDescription)")))
            return
        }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.listeningWindow))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func finish() {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        isListening = false
        // ponytail: the audio session stays active (mixWithOthers, so harmless);
        // deactivate here if battery profiling ever flags it.
    }
}
