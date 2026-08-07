import AVFoundation
import Foundation

/// Exposure profile tuned for lightning: night gathers light, day freezes it.
enum CameraExposureProfile {
    case night
    case day

    /// ponytail: picked by local clock hour, not ambient metering. Upgrade path:
    /// derive from the measured baseline luma instead.
    static func current(date: Date = Date()) -> CameraExposureProfile {
        let hour = Calendar.current.component(.hour, from: date)
        return (7..<19).contains(hour) ? .day : .night
    }
}

/// Defensive one-shot camera configuration. Every feature is probed before use;
/// failures come back as a message instead of crashing mid-storm.
enum CameraAssistant {
    /// Applies focus/exposure/white-balance locks. Returns an error description
    /// on failure, nil on success.
    @discardableResult
    static func apply(_ profile: CameraExposureProfile, to device: AVCaptureDevice) -> String? {
        do {
            try device.lockForConfiguration()
        } catch {
            return String(localized: "camera.error.lock", defaultValue: "Kamera konnte nicht konfiguriert werden: \(error.localizedDescription)")
        }
        defer { device.unlockForConfiguration() }

        // Lightning lives at infinity; never let the lens hunt in the dark.
        if device.isFocusModeSupported(.locked) {
            if device.isLockingFocusWithCustomLensPositionSupported {
                device.setFocusModeLocked(lensPosition: 1)
            } else {
                device.focusMode = .locked
            }
        }

        if device.isExposureModeSupported(.custom) {
            let format = device.activeFormat
            let target: CMTime
            let targetISO: Float
            switch profile {
            case .night:
                target = CMTime(value: 1, timescale: 15)
                targetISO = 1600
            case .day:
                target = CMTime(value: 1, timescale: 1000)
                targetISO = 100
            }
            let duration = CMTimeMinimum(CMTimeMaximum(target, format.minExposureDuration), format.maxExposureDuration)
            let iso = max(min(targetISO, format.maxISO), format.minISO)
            device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
        }

        if device.isWhiteBalanceModeSupported(.locked) {
            device.whiteBalanceMode = .locked
        }
        return nil
    }

    static func disableStabilization(on connection: AVCaptureConnection) {
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .off
        }
    }

    /// Switches to the fastest format with >= 120 fps. Returns the achieved
    /// frame rate, or nil when the device has none (caller falls back to video).
    static func configureSlowMotion(on device: AVCaptureDevice) -> Double? {
        var best: (format: AVCaptureDevice.Format, fps: Double)?
        for format in device.formats {
            for range in format.videoSupportedFrameRateRanges where range.maxFrameRate >= 120 {
                if range.maxFrameRate > (best?.fps ?? 0) {
                    best = (format, range.maxFrameRate)
                }
            }
        }
        guard let best else { return nil }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.activeFormat = best.format
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(best.fps.rounded()))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
            return best.fps
        } catch {
            return nil
        }
    }
}
