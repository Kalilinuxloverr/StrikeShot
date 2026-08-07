import CoreGraphics
import XCTest
@testable import StrikeShot

final class PostProcessingTests: XCTestCase {

    // MARK: - Helpers

    /// Black canvas plus whatever `draw` adds.
    private func makeImage(size: Int = 128, draw: (CGContext) -> Void = { _ in }) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        draw(context)
        return try XCTUnwrap(context.makeImage())
    }

    /// Mean luma of one pixel column. Columns are immune to the vertical
    /// flip between CG user space and bitmap memory order.
    private func averageColumnLuma(of image: CGImage, column: Int) throws -> Double {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var sum = 0.0
        for row in 0..<height {
            let i = (row * width + column) * 4
            sum += 0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.114 * Double(pixels[i + 2])
        }
        return sum / Double(height)
    }

    // MARK: - BestShotRanker

    func testBoltScoresClearlyAboveBlack() throws {
        let black = try makeImage()
        let bolt = try makeImage { context in
            context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.setLineWidth(6)
            context.move(to: CGPoint(x: 8, y: 8))
            context.addLine(to: CGPoint(x: 70, y: 60))
            context.addLine(to: CGPoint(x: 55, y: 75))
            context.addLine(to: CGPoint(x: 120, y: 120))
            context.strokePath()
        }

        let blackScore = BestShotRanker.score(image: black)
        let boltScore = BestShotRanker.score(image: bolt)

        XCTAssertLessThan(blackScore, 0.1, "pure black must score near zero")
        XCTAssertGreaterThan(boltScore, blackScore + 0.3, "a bright branched bolt must clearly outscore black")
    }

    // MARK: - CompositeStacker

    func testStackKeepsBrightRegionsFromBothImages() throws {
        let size = 128
        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let left = try makeImage(size: size) { context in
            context.setFillColor(white)
            context.fill(CGRect(x: 10, y: 0, width: 12, height: size))
        }
        let right = try makeImage(size: size) { context in
            context.setFillColor(white)
            context.fill(CGRect(x: 100, y: 0, width: 12, height: size))
        }

        let composite = try XCTUnwrap(CompositeStacker.stack(images: [left, right]))

        XCTAssertGreaterThan(try averageColumnLuma(of: composite, column: 15), 200, "left stripe must survive")
        XCTAssertGreaterThan(try averageColumnLuma(of: composite, column: 105), 200, "right stripe must survive")
        XCTAssertLessThan(try averageColumnLuma(of: composite, column: 60), 30, "untouched area must stay dark")
    }

    func testStackEmptyInputReturnsNil() {
        XCTAssertNil(CompositeStacker.stack(images: []))
    }
}
