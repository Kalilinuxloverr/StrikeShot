import AVFoundation
import CoreImage
import Foundation
import Photos
import UIKit

enum CaptureMode: String, CaseIterable, Identifiable, Codable {
    case photo, video, slowMotion

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .photo: String(localized: "capture.mode.photo", defaultValue: "Foto")
        case .video: String(localized: "capture.mode.video", defaultValue: "Video")
        case .slowMotion: String(localized: "capture.mode.slowMotion", defaultValue: "Zeitlupe")
        }
    }

    var symbolName: String {
        switch self {
        case .photo: "camera.fill"
        case .video: "video.fill"
        case .slowMotion: "slowmo"
        }
    }
}

enum CapturePermission {
    case unknown, authorized, denied, unavailable
}

struct CaptureResult: Identifiable, Sendable {
    let id: UUID
    let mode: CaptureMode
    let date: Date
    let fileURL: URL
    var photoLibraryIdentifier: String?
    let peakLuma: Double
    var thunderDistanceMeters: Double?
    var thumbnailData: Data?
}

/// One deep-copied camera frame. Copies are mandatory: retaining the capture
/// pool's own buffers stalls frame delivery within a second.
private struct BufferedFrame {
    let pixelBuffer: CVPixelBuffer
    let presentationTime: CMTime
    let luma: Double
}

private let photoContext = CIContext()

/// Owns the AVCaptureSession, the flash trigger pipeline, and the capture
/// output paths (photo, video, slow motion). On the iOS simulator it runs the
/// synthetic `CaptureSimulator` feed instead of a camera.
@MainActor
@Observable
final class CaptureController {
    var onCapture: ((CaptureResult) -> Void)?
    var mode: CaptureMode = .photo {
        didSet {
            guard oldValue != mode else { return }
            applyMode()
        }
    }

    private(set) var isRunning = false
    private(set) var isArmed = false
    private(set) var permission: CapturePermission = .unknown
    private(set) var recentCaptures: [CaptureResult] = []
    private(set) var triggerCount = 0
    private(set) var lastTrigger: Date?
    private(set) var currentLuma: Double = 0
    private(set) var baselineLuma: Double = 0
    private(set) var lastThunderDistanceMeters: Double?
    var lastError: String?
    let session = AVCaptureSession()

    private let settings: SettingsStore
    private let sessionQueue = DispatchQueue(label: "dev.leonfrohlich.strikeshot.session")
    private let pipeline: CaptureVideoPipeline
    private let thunder = ThunderRanger()
    private let capturesDirectory: URL
    private var activeDevice: AVCaptureDevice?
    private var sessionConfigured = false
    private var simulatorTask: Task<Void, Never>?
    private var thunderDistanceForTrigger: Double?
    private var pushedSensitivity: Double

    init(settings: SettingsStore) {
        self.settings = settings
        pushedSensitivity = settings.triggerSensitivity

        var directory = FileManager.default.temporaryDirectory
        var directoryError: String?
        do {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            let captures = documents.appendingPathComponent("Captures", isDirectory: true)
            try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
            directory = captures
        } catch {
            // Fall back to tmp so captures still work for this session.
            directoryError = error.localizedDescription
        }
        capturesDirectory = directory
        pipeline = CaptureVideoPipeline(directory: directory, sensitivity: settings.triggerSensitivity)
        if let directoryError {
            lastError = String(localized: "capture.error.directory",
                               defaultValue: "Aufnahme-Ordner konnte nicht angelegt werden: \(directoryError)")
        }
        wirePipeline()
    }

    // MARK: - Lifecycle

    func start() async {
        guard !isRunning else { return }
        #if targetEnvironment(simulator)
        permission = .unavailable
        lastError = String(localized: "capture.error.noCameraSimulator",
                           defaultValue: "Im iOS-Simulator gibt es keine Kamera. Starte die Blitz-Simulation, um die Auslösung zu testen.")
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .authorized
        case .notDetermined:
            permission = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        case .denied, .restricted:
            permission = .denied
        @unknown default:
            permission = .denied
        }
        guard permission == .authorized else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            permission = .unavailable
            lastError = String(localized: "capture.error.noCamera", defaultValue: "Keine Rückkamera gefunden.")
            return
        }
        activeDevice = device
        if sessionConfigured {
            let session = self.session
            sessionQueue.async {
                if !session.isRunning { session.startRunning() }
            }
            isRunning = true
        } else {
            sessionConfigured = true
            configureSession(with: device)
        }
        if mode != .photo { applyMode() }
        #endif
    }

    func stop() {
        isArmed = false
        pipeline.setArmed(false)
        pipeline.flush()
        thunder.cancel()
        simulatorTask?.cancel()
        simulatorTask = nil
        let session = self.session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
        isRunning = false
    }

    func arm() {
        isArmed = true
        pipeline.setSensitivity(settings.triggerSensitivity)
        pipeline.setArmed(true)
    }

    func disarm() {
        isArmed = false
        pipeline.setArmed(false)
    }

    func manualTrigger() {
        if simulatorTask != nil {
            simulatedTrigger(peakLuma: max(currentLuma, 0.85))
        } else if isRunning {
            pipeline.triggerManually()
        } else {
            lastError = String(localized: "capture.error.notRunning", defaultValue: "Die Kamera läuft nicht.")
        }
    }

    /// Synthetic feed for camera-less environments (iOS simulator).
    func startSimulation() {
        guard simulatorTask == nil else { return }
        isRunning = true
        let started = Date()
        var simulator = CaptureSimulator()
        var detector = LumaSpikeDetector(sensitivity: settings.triggerSensitivity)
        // ponytail: 30 Hz loop on the main actor; per-tick work is trivial.
        simulatorTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(33))
                } catch {
                    return
                }
                guard let self else { return }
                let time = Date().timeIntervalSince(started)
                detector.sensitivity = self.settings.triggerSensitivity
                let luma = simulator.luma(at: time)
                let fired = detector.ingest(luma: luma, at: time)
                self.currentLuma = luma
                self.baselineLuma = detector.baseline
                if fired, self.isArmed {
                    self.simulatedTrigger(peakLuma: luma)
                }
            }
        }
    }

    // MARK: - Session configuration (device only)

    private func configureSession(with device: AVCaptureDevice) {
        let session = self.session
        let pipeline = self.pipeline
        sessionQueue.async { [weak self] in
            session.beginConfiguration()
            var failure: String?
            if session.canSetSessionPreset(.hd1280x720) {
                session.sessionPreset = .hd1280x720
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                } else {
                    failure = String(localized: "capture.error.input", defaultValue: "Kamera-Eingang wurde abgelehnt.")
                }
            } catch {
                failure = error.localizedDescription
            }
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(pipeline, queue: pipeline.queue)
            if session.canAddOutput(output) {
                session.addOutput(output)
            } else if failure == nil {
                failure = String(localized: "capture.error.output", defaultValue: "Video-Ausgang wurde abgelehnt.")
            }
            if let connection = output.connection(with: .video) {
                CameraAssistant.disableStabilization(on: connection)
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
            let exposureIssue = CameraAssistant.apply(.current(), to: device)
            session.commitConfiguration()
            session.startRunning()
            DispatchQueue.main.async {
                guard let self else { return }
                if let failure {
                    self.lastError = String(localized: "capture.error.configure",
                                            defaultValue: "Kamera-Konfiguration fehlgeschlagen: \(failure)")
                } else {
                    self.isRunning = session.isRunning
                    if let exposureIssue { self.lastError = exposureIssue }
                }
            }
        }
    }

    private func applyMode() {
        pipeline.setMode(mode)
        guard let device = activeDevice else { return }
        let session = self.session
        let mode = self.mode
        sessionQueue.async { [weak self] in
            session.beginConfiguration()
            var slowMotionFailed = false
            if mode == .slowMotion {
                slowMotionFailed = CameraAssistant.configureSlowMotion(on: device) == nil
            }
            if mode != .slowMotion || slowMotionFailed {
                if session.canSetSessionPreset(.hd1280x720) {
                    session.sessionPreset = .hd1280x720
                }
            }
            let exposureIssue = CameraAssistant.apply(.current(), to: device)
            session.commitConfiguration()
            DispatchQueue.main.async {
                guard let self else { return }
                if slowMotionFailed {
                    self.lastError = String(localized: "capture.error.noSlowMotion",
                                            defaultValue: "Zeitlupe wird von dieser Kamera nicht unterstützt – Video-Modus aktiv.")
                    self.mode = .video
                } else if let exposureIssue {
                    self.lastError = exposureIssue
                }
            }
        }
    }

    // MARK: - Pipeline wiring

    private func wirePipeline() {
        pipeline.onLuma = { [weak self] luma, baseline in
            DispatchQueue.main.async {
                guard let self else { return }
                self.currentLuma = luma
                self.baselineLuma = baseline
                let sensitivity = self.settings.triggerSensitivity
                if sensitivity != self.pushedSensitivity {
                    self.pushedSensitivity = sensitivity
                    self.pipeline.setSensitivity(sensitivity)
                }
            }
        }
        pipeline.onTriggered = { [weak self] in
            DispatchQueue.main.async { self?.registerTrigger() }
        }
        pipeline.onPhotoFrame = { [weak self] frame in
            DispatchQueue.main.async { self?.processPhoto(frame) }
        }
        pipeline.onVideoFinished = { [weak self] url, peakFrame, slowMotion in
            DispatchQueue.main.async { self?.processVideo(url: url, peakFrame: peakFrame, slowMotion: slowMotion) }
        }
        pipeline.onIssue = { [weak self] message in
            DispatchQueue.main.async { self?.lastError = message }
        }
    }

    // MARK: - Trigger handling

    private func registerTrigger() {
        triggerCount += 1
        let flash = Date()
        lastTrigger = flash
        thunderDistanceForTrigger = nil
        guard settings.thunderRangingEnabled else { return }
        thunder.beginRanging(flashAt: flash) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .distance(let meters):
                self.lastThunderDistanceMeters = meters
                self.thunderDistanceForTrigger = meters
                // Attach to the capture that belongs to this flash, if it is
                // already published (video finishes seconds after the trigger).
                if let index = self.recentCaptures.lastIndex(where: { $0.date >= flash }) {
                    self.recentCaptures[index].thunderDistanceMeters = meters
                }
            case .failed(let message):
                self.lastError = message
            }
        }
    }

    private func processPhoto(_ frame: BufferedFrame) {
        let directory = capturesDirectory
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let image = CaptureController.image(from: frame.pixelBuffer),
                  let data = image.jpegData(compressionQuality: 0.9) else {
                await MainActor.run {
                    self?.lastError = String(localized: "capture.error.encode",
                                             defaultValue: "Foto konnte nicht kodiert werden.")
                }
                return
            }
            let url = directory.appendingPathComponent("strike-\(UUID().uuidString).jpg")
            do {
                try data.write(to: url)
            } catch {
                await MainActor.run {
                    self?.lastError = String(localized: "capture.error.write",
                                             defaultValue: "Foto konnte nicht gespeichert werden: \(error.localizedDescription)")
                }
                return
            }
            let thumbnail = CaptureController.thumbnailData(from: image)
            await MainActor.run {
                self?.finishCapture(url: url, mode: .photo, peakLuma: frame.luma, thumbnail: thumbnail)
            }
        }
    }

    private func processVideo(url: URL, peakFrame: BufferedFrame, slowMotion: Bool) {
        Task.detached(priority: .userInitiated) { [weak self] in
            var thumbnail: Data?
            if let image = CaptureController.image(from: peakFrame.pixelBuffer) {
                thumbnail = CaptureController.thumbnailData(from: image)
            }
            await MainActor.run {
                self?.finishCapture(url: url, mode: slowMotion ? .slowMotion : .video,
                                    peakLuma: peakFrame.luma, thumbnail: thumbnail)
            }
        }
    }

    private func simulatedTrigger(peakLuma: Double) {
        registerTrigger()
        let mode = self.mode
        let directory = capturesDirectory
        Task.detached(priority: .utility) { [weak self] in
            let image = CaptureController.placeholderImage(peakLuma: peakLuma)
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            let url = directory.appendingPathComponent("strike-sim-\(UUID().uuidString).jpg")
            do {
                try data.write(to: url)
            } catch {
                await MainActor.run {
                    self?.lastError = String(localized: "capture.error.write",
                                             defaultValue: "Foto konnte nicht gespeichert werden: \(error.localizedDescription)")
                }
                return
            }
            let thumbnail = CaptureController.thumbnailData(from: image)
            await MainActor.run {
                // ponytail: the simulator always produces a still placeholder tagged
                // with the selected mode, and never touches the photo library.
                self?.finishCapture(url: url, mode: mode, peakLuma: peakLuma,
                                    thumbnail: thumbnail, allowLibrarySave: false)
            }
        }
    }

    private func finishCapture(url: URL, mode: CaptureMode, peakLuma: Double,
                               thumbnail: Data?, allowLibrarySave: Bool = true) {
        let result = CaptureResult(
            id: UUID(),
            mode: mode,
            date: Date(),
            fileURL: url,
            photoLibraryIdentifier: nil,
            peakLuma: peakLuma,
            thunderDistanceMeters: thunderDistanceForTrigger,
            thumbnailData: thumbnail
        )
        recentCaptures.insert(result, at: 0)
        if recentCaptures.count > 12 {
            recentCaptures.removeLast(recentCaptures.count - 12)
        }
        onCapture?(result)
        if allowLibrarySave, settings.saveToPhotoLibrary {
            Task { await self.saveToPhotoLibrary(result) }
        }
    }

    private func saveToPhotoLibrary(_ result: CaptureResult) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            lastError = String(localized: "capture.error.photoLibraryDenied",
                               defaultValue: "Kein Zugriff auf die Fotomediathek – die Aufnahme bleibt in der App.")
            return
        }
        let resourceType: PHAssetResourceType = result.mode == .photo ? .photo : .video
        let fileURL = result.fileURL
        do {
            var identifier: String?
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: resourceType, fileURL: fileURL, options: nil)
                identifier = request.placeholderForCreatedAsset?.localIdentifier
            }
            if let identifier, let index = recentCaptures.firstIndex(where: { $0.id == result.id }) {
                recentCaptures[index].photoLibraryIdentifier = identifier
            }
        } catch {
            lastError = String(localized: "capture.error.photoLibrarySave",
                               defaultValue: "Speichern in der Fotomediathek fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    // MARK: - Image helpers (off-main safe)

    nonisolated fileprivate static func image(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = photoContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    nonisolated fileprivate static func thumbnailData(from image: UIImage, maxWidth: CGFloat = 240) -> Data? {
        let width = max(image.size.width, 1)
        guard width > maxWidth else { return image.jpegData(compressionQuality: 0.7) }
        let scale = maxWidth / width
        let size = CGSize(width: maxWidth, height: image.size.height * scale)
        let thumbnail = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return thumbnail.jpegData(compressionQuality: 0.7)
    }

    /// Grayscale night sky with the app's bolt — recognizably fake on purpose.
    nonisolated fileprivate static func placeholderImage(peakLuma: Double) -> UIImage {
        let size = CGSize(width: 800, height: 600)
        return UIGraphicsImageRenderer(size: size).image { context in
            let ctx = context.cgContext
            UIColor(white: 0.04, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.42)
            let colors = [UIColor(white: 1, alpha: 0.55 * peakLuma).cgColor,
                          UIColor(white: 1, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 1]) {
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: size.height * 0.5, options: [])
            }
            let boltRect = CGRect(x: size.width * 0.38, y: size.height * 0.15,
                                  width: size.width * 0.24, height: size.height * 0.6)
            ctx.addPath(BoltShape().path(in: boltRect).cgPath)
            ctx.setFillColor(UIColor(white: 0.98, alpha: 0.95).cgColor)
            ctx.fillPath()
        }
    }
}

// MARK: - Video pipeline (runs on its own queue)

/// Sample-buffer delegate: per-frame luma, ring buffering, trigger dispatch and
/// the AVAssetWriter recording path. All mutable state is confined to `queue`.
private final class CaptureVideoPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "dev.leonfrohlich.strikeshot.video")

    private var detector: LumaSpikeDetector
    private let ring = FrameRingBuffer<BufferedFrame>()
    private let directory: URL
    private var armed = false
    private var mode: CaptureMode = .photo
    private var frameIndex = 0

    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var writerAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var writerStart = CMTime.invalid
    private var writerDeadline = CMTime.invalid
    private var writerSlowFactor: Int32 = 1
    private var writerIsSlowMotion = false
    private var writerPeak: BufferedFrame?

    // Callbacks fire on `queue`; the controller hops to the main actor.
    var onLuma: ((Double, Double) -> Void)?
    var onTriggered: (() -> Void)?
    var onPhotoFrame: ((BufferedFrame) -> Void)?
    var onVideoFinished: ((URL, BufferedFrame, Bool) -> Void)?
    var onIssue: ((String) -> Void)?

    init(directory: URL, sensitivity: Double) {
        self.directory = directory
        detector = LumaSpikeDetector(sensitivity: sensitivity)
    }

    func setArmed(_ armed: Bool) {
        queue.async { self.armed = armed }
    }

    func setSensitivity(_ value: Double) {
        queue.async { self.detector.sensitivity = value }
    }

    func setMode(_ mode: CaptureMode) {
        queue.async {
            self.mode = mode
            self.ring.removeAll()
            self.detector.reset()
        }
    }

    func triggerManually() {
        queue.async {
            guard self.writer == nil else { return }
            self.fire()
        }
    }

    /// Ends a recording that would otherwise wait forever for frames.
    func flush() {
        queue.async { self.finishWriter() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let luma = Self.meanLuma(of: source)
        guard let copy = Self.deepCopy(source) else { return } // allocation failure: drop the frame
        let frame = BufferedFrame(pixelBuffer: copy, presentationTime: pts, luma: luma)
        ring.append(frame, time: pts.seconds, cost: CVPixelBufferGetDataSize(copy))
        let fired = detector.ingest(luma: luma, at: pts.seconds)
        frameIndex += 1
        if frameIndex % 3 == 0 {
            onLuma?(luma, detector.baseline)
        }
        if writer != nil {
            appendToWriter(frame)
        } else if fired, armed {
            fire()
        }
    }

    private func fire() {
        onTriggered?()
        switch mode {
        case .photo:
            let frames = ring.snapshot()
            guard let best = frames.max(by: { $0.element.luma < $1.element.luma })?.element else {
                onIssue?(String(localized: "capture.error.emptyBuffer",
                                defaultValue: "Kein Bildmaterial im Puffer."))
                return
            }
            onPhotoFrame?(best)
        case .video, .slowMotion:
            startWriter(slowMotion: mode == .slowMotion)
        }
    }

    private func startWriter(slowMotion: Bool) {
        let frames = ring.snapshot().map(\.element)
        guard let first = frames.first, let last = frames.last else {
            onIssue?(String(localized: "capture.error.emptyBuffer",
                            defaultValue: "Kein Bildmaterial im Puffer."))
            return
        }
        let width = CVPixelBufferGetWidth(first.pixelBuffer)
        let height = CVPixelBufferGetHeight(first.pixelBuffer)
        let url = directory.appendingPathComponent("strike-\(UUID().uuidString).mov")
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            onIssue?(error.localizedDescription)
            return
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else {
            onIssue?(String(localized: "capture.error.writerInput",
                            defaultValue: "Video-Aufnahme konnte nicht vorbereitet werden."))
            return
        }
        writer.add(input)
        guard writer.startWriting() else {
            onIssue?(writer.error?.localizedDescription ?? String(localized: "capture.error.videoWrite",
                                                                  defaultValue: "Video konnte nicht gespeichert werden."))
            return
        }
        writer.startSession(atSourceTime: first.presentationTime)
        self.writer = writer
        writerInput = input
        writerAdaptor = adaptor
        writerStart = first.presentationTime
        writerSlowFactor = slowMotion ? 4 : 1
        writerIsSlowMotion = slowMotion
        writerDeadline = CMTimeAdd(last.presentationTime, CMTime(seconds: 3, preferredTimescale: 600))
        writerPeak = nil
        for frame in frames {
            appendToWriter(frame)
        }
    }

    private func appendToWriter(_ frame: BufferedFrame) {
        guard let input = writerInput, let adaptor = writerAdaptor else { return }
        if frame.luma > (writerPeak?.luma ?? -1) {
            writerPeak = frame
        }
        if input.isReadyForMoreMediaData {
            // Slow motion = stretch the timestamps; capture stays real-time.
            let relative = CMTimeSubtract(frame.presentationTime, writerStart)
            let scaled = CMTimeAdd(writerStart, CMTimeMultiply(relative, multiplier: writerSlowFactor))
            adaptor.append(frame.pixelBuffer, withPresentationTime: scaled)
        }
        // ponytail: frames are dropped when the encoder is behind; acceptable here.
        if CMTimeCompare(frame.presentationTime, writerDeadline) >= 0 {
            finishWriter()
        }
    }

    private func finishWriter() {
        guard let writer, let input = writerInput else { return }
        let peak = writerPeak
        let slow = writerIsSlowMotion
        self.writer = nil
        writerInput = nil
        writerAdaptor = nil
        writerPeak = nil
        writerStart = .invalid
        writerDeadline = .invalid
        input.markAsFinished()
        writer.finishWriting { [weak self] in
            if writer.status == .completed, let peak {
                self?.onVideoFinished?(writer.outputURL, peak, slow)
            } else {
                self?.onIssue?(writer.error?.localizedDescription
                    ?? String(localized: "capture.error.videoWrite",
                              defaultValue: "Video konnte nicht gespeichert werden."))
            }
        }
    }

    // MARK: Frame math

    /// Mean luma by sampling a ~64×64 grid — no CoreImage, cheap enough per frame.
    private static func meanLuma(of pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let stepX = max(1, width / 64)
        let stepY = max(1, height / 64)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var total = 0.0
        var count = 0
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let offset = y * bytesPerRow + x * 4 // BGRA
                let b = Double(pixels[offset])
                let g = Double(pixels[offset + 1])
                let r = Double(pixels[offset + 2])
                total += 0.114 * b + 0.587 * g + 0.299 * r
                count += 1
                x += stepX
            }
            y += stepY
        }
        return count > 0 ? total / (255 * Double(count)) : 0
    }

    // ponytail: one CVPixelBufferCreate per frame; switch to a CVPixelBufferPool
    // if allocation churn ever shows up in Instruments.
    private static func deepCopy(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        var copy: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, width, height,
                                         CVPixelBufferGetPixelFormatType(source), nil, &copy)
        guard status == kCVReturnSuccess, let destination = copy else { return nil }
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destination, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        guard let sourceBase = CVPixelBufferGetBaseAddress(source),
              let destinationBase = CVPixelBufferGetBaseAddress(destination) else { return nil }
        let sourceBPR = CVPixelBufferGetBytesPerRow(source)
        let destinationBPR = CVPixelBufferGetBytesPerRow(destination)
        if sourceBPR == destinationBPR {
            memcpy(destinationBase, sourceBase, sourceBPR * height)
        } else {
            let rowBytes = min(sourceBPR, destinationBPR)
            for row in 0..<height {
                memcpy(destinationBase + row * destinationBPR, sourceBase + row * sourceBPR, rowBytes)
            }
        }
        return destination
    }
}
