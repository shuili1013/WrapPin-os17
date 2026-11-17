// Offline check for area drift geometry and the drift engine.
// xcrun swiftc -parse-as-library scripts/test-area-drift.swift \
//   WrapPin/Models/DriftArea.swift -o /tmp/drift-check && /tmp/drift-check

import Foundation

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@main
struct AreaDriftCheck {
    static func main() throws {
        var rng = SplitMix64(state: 42)

        // Taipei and a high-latitude box, both well inside limits.
        let areas = [
            DriftArea(name: "Taipei", centerLatitude: 25.0418, centerLongitude: 121.5654,
                      widthMetres: 300, heightMetres: 120),
            DriftArea(name: "Oslo", centerLatitude: 59.91, centerLongitude: 10.75,
                      widthMetres: 50, heightMetres: 800)
        ]

        for area in areas {
            // Corners round-trip and span the stated size.
            let corners = area.corners
            precondition(corners.count == 4)
            let nw = area.offset(latitude: corners[0].latitude, longitude: corners[0].longitude)
            let se = area.offset(latitude: corners[2].latitude, longitude: corners[2].longitude)
            precondition(abs((se.x - nw.x) - area.widthMetres) < 0.01)
            precondition(abs((nw.y - se.y) - area.heightMetres) < 0.01)

            // Rebuilding from two corners gives the same box.
            let rebuilt = DriftArea(name: "r", corner: corners[0], corner: corners[2])
            precondition(abs(rebuilt.widthMetres - area.widthMetres) < 0.5)
            precondition(abs(rebuilt.heightMetres - area.heightMetres) < 0.5)
            precondition(abs(rebuilt.centerLatitude - area.centerLatitude) < 1e-9)

            for mode in DriftMode.allCases {
                var settings = DriftSettings()
                settings.mode = mode
                settings.wanderSpeedKilometresPerHour = 30
                settings.jumpIntervalSeconds = 3
                settings.maximumPauseSeconds = 5
                var engine = DriftEngine(area: area, settings: settings, using: &rng)
                var distinct = Set<String>()
                var maxStep = 0.0
                var previous = engine.coordinate
                for tick in 0..<3_000 {
                    let point = engine.step(elapsed: tick % 97 == 0 ? 9.5 : 1, using: &rng)
                    let offset = area.offset(latitude: point.latitude, longitude: point.longitude)
                    precondition(area.contains(x: offset.x, y: offset.y),
                                 "\(mode) left \(area.name) at tick \(tick): \(offset)")
                    if mode == .jitter {
                        let r = (offset.x * offset.x + offset.y * offset.y).squareRoot()
                        precondition(r <= settings.jitterRadiusMetres + 0.01, "jitter radius exceeded")
                    }
                    let before = area.offset(latitude: previous.latitude, longitude: previous.longitude)
                    let moved = ((offset.x - before.x) * (offset.x - before.x)
                        + (offset.y - before.y) * (offset.y - before.y)).squareRoot()
                    if mode == .wander, tick % 97 != 0 { maxStep = max(maxStep, moved) }
                    previous = point
                    distinct.insert(String(format: "%.6f,%.6f", point.latitude, point.longitude))
                }
                precondition(distinct.count > 20, "\(mode) barely moved in \(area.name)")
                if mode == .wander {
                    // 30 km/h ≈ 8.33 m/s; one-second ticks must respect the speed.
                    precondition(maxStep <= 30 / 3.6 + 0.01, "wander moved too fast: \(maxStep)")
                }
            }
        }

        // Starting outside the box is pulled back in.
        var settings = DriftSettings()
        settings.mode = .wander
        let area = areas[0]
        let outside = area.coordinate(x: 10_000, y: -10_000)
        let engine = DriftEngine(area: area, settings: settings, start: outside, using: &rng)
        let start = area.offset(latitude: engine.coordinate.latitude, longitude: engine.coordinate.longitude)
        precondition(area.contains(x: start.x, y: start.y))

        // Sizes and settings are clamped.
        precondition(DriftArea.clampSide(1) == DriftArea.minimumSideMetres)
        precondition(DriftArea.clampSide(.infinity) == DriftArea.minimumSideMetres)
        precondition(DriftArea.clampSide(1e9) == DriftArea.maximumSideMetres)
        var wild = DriftSettings()
        wild.wanderSpeedKilometresPerHour = 500
        wild.jumpIntervalSeconds = 0
        wild.jitterRadiusMetres = .nan
        let safe = wild.sanitised()
        precondition(safe.wanderSpeedKilometresPerHour == DriftSettings.wanderSpeedRange.upperBound)
        precondition(safe.jumpIntervalSeconds == DriftSettings.jumpIntervalRange.lowerBound)
        precondition(safe.jitterRadiusMetres == DriftSettings.jitterRadiusRange.lowerBound)

        // Saved areas and settings survive a JSON round trip.
        let data = try JSONEncoder().encode(areas)
        let decoded = try JSONDecoder().decode([DriftArea].self, from: data)
        precondition(decoded == areas)
        let settingsData = try JSONEncoder().encode(safe)
        let decodedSettings = try JSONDecoder().decode(DriftSettings.self, from: settingsData)
        precondition(decodedSettings == safe)

        print("Area drift checks passed.")
    }
}
