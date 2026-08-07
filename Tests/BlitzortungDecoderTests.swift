import XCTest
@testable import StrikeShot

final class BlitzortungDecoderTests: XCTestCase {

    // MARK: - Reference compressor (test-only counterpart of decompress)

    /// Standard LZW matching the decoder: single characters are literal codes,
    /// dictionary codes start at 256 and grow one per emitted token.
    private func compress(_ input: String) -> String {
        var dictionary: [String: Int] = [:]
        var nextCode = 256
        var phrase = ""
        var output = ""

        func append(codeFor phrase: String) {
            let scalars = Array(phrase.unicodeScalars)
            let code = scalars.count == 1 ? Int(scalars[0].value) : (dictionary[phrase] ?? -1)
            guard code >= 0, let scalar = Unicode.Scalar(UInt32(code)) else {
                XCTFail("reference compressor broke on \(phrase)")
                return
            }
            output.unicodeScalars.append(scalar)
        }

        for character in input.unicodeScalars.map({ String(Character($0)) }) {
            let candidate = phrase + character
            if candidate.unicodeScalars.count == 1 || dictionary[candidate] != nil {
                phrase = candidate
            } else {
                append(codeFor: phrase)
                dictionary[candidate] = nextCode
                nextCode += 1
                phrase = character
            }
        }
        if !phrase.isEmpty { append(codeFor: phrase) }
        return output
    }

    // MARK: - decompress

    func testRoundtripRestoresOriginal() {
        let samples = [
            "",
            "x",
            "hello hello hello hello",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "abababababababababab",
            #"{"time":1717171717000000000,"lat":48.137,"lon":11.575}"#,
            #"{"ort":"Müncheberg","straße":"Über den Höfen 7","größe":"12 m²","grad":"3°"}"#,
        ]
        for sample in samples {
            XCTAssertEqual(BlitzortungDecoder.decompress(compress(sample)), sample, "failed for: \(sample)")
        }
    }

    func testDecompressGarbageDoesNotCrash() {
        // Scalars >= 256 that never match a dictionary entry.
        _ = BlitzortungDecoder.decompress("ĀĂĄxyzĀ")
        _ = BlitzortungDecoder.decompress("Ā")
        XCTAssertEqual(BlitzortungDecoder.decompress(""), "")
    }

    // MARK: - strike(fromJSONObject:)

    func testStrikeFromJSONObjectConvertsNanosecondsAndCoordinates() throws {
        let object: [String: Any] = [
            "time": Int64(1_754_000_000_123_456_789),
            "lat": 48.2,
            "lon": 11.6,
        ]
        let strike = try XCTUnwrap(BlitzortungDecoder.strike(fromJSONObject: object))
        XCTAssertEqual(strike.point.latitude, 48.2, accuracy: 1e-9)
        XCTAssertEqual(strike.point.longitude, 11.6, accuracy: 1e-9)
        XCTAssertEqual(strike.time.timeIntervalSince1970, 1_754_000_000.123, accuracy: 0.01)
    }

    func testBrokenObjectsReturnNil() {
        XCTAssertNil(BlitzortungDecoder.strike(fromJSONObject: [:]))
        XCTAssertNil(BlitzortungDecoder.strike(fromJSONObject: ["time": 1, "lat": 48.0]))
        XCTAssertNil(BlitzortungDecoder.strike(fromJSONObject: ["time": "später", "lat": 48.0, "lon": 11.0]))
        XCTAssertNil(BlitzortungDecoder.strike(fromJSONObject: ["time": 1, "lat": 123.0, "lon": 11.0]))
        XCTAssertNil(BlitzortungDecoder.strike(fromJSONObject: ["time": 1, "lat": 48.0, "lon": 999.0]))
    }

    // MARK: - strike(fromPayload:)

    func testStrikeFromCompressedPayload() throws {
        let json = #"{"time":1754000000000000000,"lat":-33.9,"lon":151.2,"pol":0}"#
        let strike = try XCTUnwrap(BlitzortungDecoder.strike(fromPayload: compress(json)))
        XCTAssertEqual(strike.point.latitude, -33.9, accuracy: 1e-9)
        XCTAssertEqual(strike.point.longitude, 151.2, accuracy: 1e-9)
        XCTAssertEqual(strike.time.timeIntervalSince1970, 1_754_000_000, accuracy: 0.01)
    }

    func testBrokenPayloadsReturnNil() {
        XCTAssertNil(BlitzortungDecoder.strike(fromPayload: ""))
        XCTAssertNil(BlitzortungDecoder.strike(fromPayload: "definitely not json"))
        XCTAssertNil(BlitzortungDecoder.strike(fromPayload: "ĀĂĄ garbage"))
        XCTAssertNil(BlitzortungDecoder.strike(fromPayload: compress(#"{"lat":1}"#)))
    }
}
