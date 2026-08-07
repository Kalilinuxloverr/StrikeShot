import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Stacks frames with lighten blend: the brightest pixel wins,
/// so every bolt from the session survives into one composite.
enum CompositeStacker {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Frames of a different size are scaled to match the first one.
    /// Empty input returns nil.
    static func stack(images: [CGImage]) -> CGImage? {
        guard let first = images.first else { return nil }
        var composite = CIImage(cgImage: first)
        let extent = composite.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        for cgImage in images.dropFirst() {
            var layer = CIImage(cgImage: cgImage)
            guard layer.extent.width > 0, layer.extent.height > 0 else { continue }
            if layer.extent.size != extent.size {
                layer = layer.transformed(by: CGAffineTransform(
                    scaleX: extent.width / layer.extent.width,
                    y: extent.height / layer.extent.height
                ))
            }
            let blend = CIFilter.lightenBlendMode()
            blend.inputImage = layer
            blend.backgroundImage = composite
            guard let blended = blend.outputImage else { return nil }
            composite = blended
        }
        return ciContext.createCGImage(composite, from: extent)
    }
}
