import Foundation

/// Decodes the LZW-style packed JSON strings the blitzortung.org websocket sends.
enum BlitzortungDecoder {

    /// Inverse of the "unpack" routine used by the open Blitzortung web clients:
    /// the dictionary starts with single characters, codes from 256 grow one per
    /// token. Works scalar-wise; the feed payload is Latin-1-safe JSON.
    static func decompress(_ input: String) -> String {
        let scalars = Array(input.unicodeScalars)
        guard let first = scalars.first else { return "" }

        var dictionary: [Int: String] = [:]
        var nextCode = 256
        var previous = String(Character(first))
        var output = previous

        for scalar in scalars.dropFirst() {
            let code = Int(scalar.value)
            let entry: String
            if code < 256 {
                entry = String(Character(scalar))
            } else if let known = dictionary[code] {
                entry = known
            } else if let head = previous.unicodeScalars.first {
                // Classic LZW self-reference: code not in the dictionary yet.
                entry = previous + String(Character(head))
            } else {
                return output // corrupt stream; keep what decoded so far
            }
            output += entry
            if let head = entry.unicodeScalars.first {
                dictionary[nextCode] = previous + String(Character(head))
                nextCode += 1
            }
            previous = entry
        }
        return output
    }

    /// "time" is nanoseconds since the epoch, "lat"/"lon" in degrees.
    static func strike(fromJSONObject object: [String: Any]) -> Strike? {
        guard let nanoseconds = double(object["time"]),
              let latitude = double(object["lat"]),
              let longitude = double(object["lon"]) else { return nil }
        let point = GeoPoint(latitude: latitude, longitude: longitude)
        guard point.isValid else { return nil }
        return Strike(point: point, time: Date(timeIntervalSince1970: nanoseconds / 1_000_000_000))
    }

    static func strike(fromPayload payload: String) -> Strike? {
        // Payloads are normally packed; fall back to plain JSON just in case.
        strike(fromJSONString: decompress(payload)) ?? strike(fromJSONString: payload)
    }

    private static func strike(fromJSONString string: String) -> Strike? {
        guard let data = string.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return strike(fromJSONObject: object)
    }

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        default: return nil
        }
    }
}
