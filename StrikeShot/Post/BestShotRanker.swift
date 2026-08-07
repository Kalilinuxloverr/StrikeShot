import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO

/// Scores lightning frames: bright peak + branched edges beat flat darkness.
enum BestShotRanker {
    /// CIContext creation is expensive; one shared, thread-safe instance.
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// 0…1. Combines the top-percentile brightness of the histogram with the
    /// edge energy (CIEdges → CIAreaAverage). A pure black frame scores ~0.
    static func score(image: CGImage) -> Double {
        let input = CIImage(cgImage: image)
        let peak = topPercentileLuma(of: input)
        let edges = edgeEnergy(of: input)
        // Edge averages are tiny even for a bright bolt, so amplify before mixing.
        return min(1, max(0, 0.65 * peak + 0.35 * min(1, edges * 5)))
    }

    static func rank(_ records: [CaptureRecord]) -> [CaptureRecord] {
        records.sorted { $0.score > $1.score }
    }

    // MARK: - Image loading (shared by store and screens)

    /// Downsampled decode via ImageIO. Returns nil for unreadable files (e.g. videos).
    static func loadImage(at url: URL, maxDimension: CGFloat = 1_600) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(from: source, maxDimension: maxDimension)
    }

    static func loadImage(data: Data, maxDimension: CGFloat = 1_600) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(from: source, maxDimension: maxDimension)
    }

    private static func thumbnail(from source: CGImageSource, maxDimension: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - Metrics

    /// Mean luma of the brightest 2% of pixels, computed on a <=64 px render.
    private static func topPercentileLuma(of image: CIImage) -> Double {
        let extent = image.extent
        guard extent.width >= 1, extent.height >= 1 else { return 0 }
        let scale = min(1, 64 / max(extent.width, extent.height))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let width = max(1, Int(scaled.extent.width.rounded(.down)))
        let height = max(1, Int(scaled.extent.height.rounded(.down)))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        ciContext.render(
            scaled,
            toBitmap: &pixels,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        var lumas = [Double]()
        lumas.reserveCapacity(width * height)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            lumas.append(0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.114 * Double(pixels[i + 2]))
        }
        lumas.sort(by: >)
        let top = max(1, lumas.count / 50)
        let sum = lumas.prefix(top).reduce(0, +)
        return sum / Double(top) / 255
    }

    /// Average edge response over the whole frame, 0…1.
    private static func edgeEnergy(of image: CIImage) -> Double {
        let edges = CIFilter.edges()
        edges.inputImage = image
        edges.intensity = 1
        guard let edged = edges.outputImage?.cropped(to: image.extent) else { return 0 }
        let average = CIFilter.areaAverage()
        average.inputImage = edged
        average.extent = image.extent
        guard let output = average.outputImage else { return 0 }
        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / (3 * 255)
    }
}
