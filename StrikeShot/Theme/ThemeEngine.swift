import Foundation
import SwiftUI

/// The live theme: palette follows the time of day, accent charge follows
/// lightning activity in the watched radius.
@Observable
final class ThemeEngine {
    private(set) var theme: StormTheme = .night
    private(set) var intensity: StormIntensity = .calm

    /// Set by whoever owns the clock; injectable so tests are not time-dependent.
    var dateProvider: () -> Date = Date.init

    init() {
        refresh()
    }

    /// Call whenever a new snapshot arrives.
    func update(with snapshot: StormSnapshot) {
        intensity = snapshot.intensity
        refresh()
    }

    func refresh() {
        var base = Self.palette(for: dateProvider())
        base.charge = intensity.chargeLevel
        theme = base
    }

    /// Night → dusk → day → dusk → night across the 24 h clock.
    /// ponytail: local clock hours, not real sunrise. Swap in a solar calc if it matters.
    static func palette(for date: Date) -> StormTheme {
        let calendar = Calendar.current
        let hour = Double(calendar.component(.hour, from: date))
            + Double(calendar.component(.minute, from: date)) / 60

        switch hour {
        case 5..<8:   return .blend(.night, .dusk, amount: (hour - 5) / 3)
        case 8..<10:  return .blend(.dusk, .day, amount: (hour - 8) / 2)
        case 10..<17: return .day
        case 17..<20: return .blend(.day, .dusk, amount: (hour - 17) / 3)
        case 20..<22: return .blend(.dusk, .night, amount: (hour - 20) / 2)
        default:      return .night
        }
    }
}

extension View {
    /// Applies the engine's palette to the environment and paints the background.
    func stormThemed(_ engine: ThemeEngine) -> some View {
        environment(\.stormTheme, engine.theme)
            .background(engine.theme.background.ignoresSafeArea())
            .animation(.easeInOut(duration: 0.6), value: engine.theme)
    }
}
