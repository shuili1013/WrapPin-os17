import Foundation

// Area drift: keep the simulated location moving inside a user-drawn box.
// Pure Foundation so scripts/test-area-drift.swift can compile it alone.

/// A north-up rectangle on the map, stored as a centre plus its size.
struct DriftArea: Codable, Equatable, Identifiable, Sendable {
    static let minimumSideMetres: Double = 10
    static let maximumSideMetres: Double = 20_000

    var id: UUID
    var name: String
    var centerLatitude: Double
    var centerLongitude: Double
    /// East–west extent.
    var widthMetres: Double
    /// North–south extent.
    var heightMetres: Double
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        centerLatitude: Double,
        centerLongitude: Double,
        widthMetres: Double,
        heightMetres: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.widthMetres = Self.clampSide(widthMetres)
        self.heightMetres = Self.clampSide(heightMetres)
        self.createdAt = createdAt
    }

    /// Builds the box spanned by two opposite corners.
    init(
        id: UUID = UUID(),
        name: String,
        corner a: (latitude: Double, longitude: Double),
        corner b: (latitude: Double, longitude: Double),
        createdAt: Date = Date()
    ) {
        let centerLatitude = (a.latitude + b.latitude) / 2
        let centerLongitude = (a.longitude + b.longitude) / 2
        let metresPerDegreeLongitude = DriftGeometry.metresPerDegreeLongitude(at: centerLatitude)
        self.init(
            id: id,
            name: name,
            centerLatitude: centerLatitude,
            centerLongitude: centerLongitude,
            widthMetres: abs(a.longitude - b.longitude) * metresPerDegreeLongitude,
            heightMetres: abs(a.latitude - b.latitude) * DriftGeometry.metresPerDegreeLatitude,
            createdAt: createdAt
        )
    }

    var halfWidth: Double { widthMetres / 2 }
    var halfHeight: Double { heightMetres / 2 }

    /// Corners in order: north-west, north-east, south-east, south-west.
    var corners: [(latitude: Double, longitude: Double)] {
        [
            coordinate(x: -halfWidth, y: halfHeight),
            coordinate(x: halfWidth, y: halfHeight),
            coordinate(x: halfWidth, y: -halfHeight),
            coordinate(x: -halfWidth, y: -halfHeight)
        ]
    }

    /// Local east/north offset in metres → coordinate.
    func coordinate(x: Double, y: Double) -> (latitude: Double, longitude: Double) {
        (
            centerLatitude + y / DriftGeometry.metresPerDegreeLatitude,
            centerLongitude + x / DriftGeometry.metresPerDegreeLongitude(at: centerLatitude)
        )
    }

    /// Coordinate → local east/north offset in metres.
    func offset(latitude: Double, longitude: Double) -> (x: Double, y: Double) {
        (
            (longitude - centerLongitude) * DriftGeometry.metresPerDegreeLongitude(at: centerLatitude),
            (latitude - centerLatitude) * DriftGeometry.metresPerDegreeLatitude
        )
    }

    func contains(x: Double, y: Double, tolerance: Double = 0.001) -> Bool {
        abs(x) <= halfWidth + tolerance && abs(y) <= halfHeight + tolerance
    }

    func clamped(x: Double, y: Double) -> (x: Double, y: Double) {
        (min(max(x, -halfWidth), halfWidth), min(max(y, -halfHeight), halfHeight))
    }

    func randomOffset<G: RandomNumberGenerator>(using generator: inout G) -> (x: Double, y: Double) {
        (
            Double.random(in: -halfWidth...halfWidth, using: &generator),
            Double.random(in: -halfHeight...halfHeight, using: &generator)
        )
    }

    static func clampSide(_ value: Double) -> Double {
        guard value.isFinite else { return minimumSideMetres }
        return min(max(value, minimumSideMetres), maximumSideMetres)
    }
}

enum DriftGeometry {
    static let metresPerDegreeLatitude = 110_540.0

    static func metresPerDegreeLongitude(at latitude: Double) -> Double {
        max(111_320.0 * cos(latitude * .pi / 180), 1)
    }
}

enum DriftMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Walk to random points inside the box, pausing now and then.
    case wander
    /// Jump straight to a random point every few seconds.
    case jump
    /// Small GPS-like wobble around the box centre.
    case jitter

    var id: Self { self }
}

struct DriftSettings: Codable, Equatable, Sendable {
    static let wanderSpeedRange: ClosedRange<Double> = 1...30
    static let maximumPauseRange: ClosedRange<Double> = 0...120
    static let jumpIntervalRange: ClosedRange<Double> = 3...300
    static let jitterRadiusRange: ClosedRange<Double> = 2...50

    var mode: DriftMode = .wander
    var wanderSpeedKilometresPerHour: Double = 4
    /// Longest stop at a waypoint; each stop is random between 0 and this.
    var maximumPauseSeconds: Double = 20
    var jumpIntervalSeconds: Double = 30
    var jitterRadiusMetres: Double = 8

    var wanderSpeedMetresPerSecond: Double {
        min(max(wanderSpeedKilometresPerHour, Self.wanderSpeedRange.lowerBound), Self.wanderSpeedRange.upperBound) / 3.6
    }

    func sanitised() -> DriftSettings {
        var copy = self
        copy.wanderSpeedKilometresPerHour = Self.clamp(wanderSpeedKilometresPerHour, Self.wanderSpeedRange)
        copy.maximumPauseSeconds = Self.clamp(maximumPauseSeconds, Self.maximumPauseRange)
        copy.jumpIntervalSeconds = Self.clamp(jumpIntervalSeconds, Self.jumpIntervalRange)
        copy.jitterRadiusMetres = Self.clamp(jitterRadiusMetres, Self.jitterRadiusRange)
        return copy
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Advances the drifting position. Works in local metres around the box centre
/// and never leaves the box.
struct DriftEngine {
    private(set) var area: DriftArea
    var settings: DriftSettings
    private(set) var x: Double = 0
    private(set) var y: Double = 0
    private var targetX: Double = 0
    private var targetY: Double = 0
    private var pauseRemaining: Double = 0
    private var sinceLastJump: Double = 0

    init<G: RandomNumberGenerator>(
        area: DriftArea,
        settings: DriftSettings,
        start: (latitude: Double, longitude: Double)? = nil,
        using generator: inout G
    ) {
        self.area = area
        self.settings = settings.sanitised()
        if let start {
            let offset = area.offset(latitude: start.latitude, longitude: start.longitude)
            (x, y) = area.clamped(x: offset.x, y: offset.y)
        } else if self.settings.mode == .jitter {
            (x, y) = (0, 0)
        } else {
            (x, y) = area.randomOffset(using: &generator)
        }
        chooseTarget(using: &generator)
    }

    var coordinate: (latitude: Double, longitude: Double) {
        area.coordinate(x: x, y: y)
    }

    var isPausedAtWaypoint: Bool { pauseRemaining > 0 }

    mutating func updateSettings<G: RandomNumberGenerator>(_ settings: DriftSettings, using generator: inout G) {
        let modeChanged = settings.mode != self.settings.mode
        self.settings = settings.sanitised()
        if modeChanged {
            pauseRemaining = 0
            sinceLastJump = 0
            chooseTarget(using: &generator)
        }
    }

    /// Moves forward by `elapsed` seconds and returns the new coordinate.
    @discardableResult
    mutating func step<G: RandomNumberGenerator>(
        elapsed: Double,
        using generator: inout G
    ) -> (latitude: Double, longitude: Double) {
        let elapsed = max(0, min(elapsed, 10))
        switch settings.mode {
        case .wander:
            stepWander(elapsed: elapsed, speed: settings.wanderSpeedMetresPerSecond, pauses: true, using: &generator)
        case .jitter:
            stepWander(elapsed: elapsed, speed: 0.6, pauses: false, using: &generator)
        case .jump:
            sinceLastJump += elapsed
            if sinceLastJump >= settings.jumpIntervalSeconds {
                sinceLastJump = 0
                (x, y) = area.randomOffset(using: &generator)
            }
        }
        (x, y) = area.clamped(x: x, y: y)
        return coordinate
    }

    private mutating func stepWander<G: RandomNumberGenerator>(
        elapsed: Double,
        speed: Double,
        pauses: Bool,
        using generator: inout G
    ) {
        var remaining = elapsed
        // Several short hops can fit in one tick at high speed.
        for _ in 0..<8 where remaining > 0 {
            if pauseRemaining > 0 {
                let used = min(pauseRemaining, remaining)
                pauseRemaining -= used
                remaining -= used
                continue
            }
            let dx = targetX - x
            let dy = targetY - y
            let distance = (dx * dx + dy * dy).squareRoot()
            let reach = speed * remaining
            if distance <= reach || distance < 0.01 {
                x = targetX
                y = targetY
                remaining -= speed > 0 ? distance / speed : remaining
                if pauses, settings.maximumPauseSeconds > 0, Bool.random(using: &generator) {
                    pauseRemaining = Double.random(in: 0...settings.maximumPauseSeconds, using: &generator)
                }
                chooseTarget(using: &generator)
            } else {
                x += dx / distance * reach
                y += dy / distance * reach
                remaining = 0
            }
        }
    }

    private mutating func chooseTarget<G: RandomNumberGenerator>(using generator: inout G) {
        switch settings.mode {
        case .wander, .jump:
            (targetX, targetY) = area.randomOffset(using: &generator)
        case .jitter:
            // A random point within the wobble radius of the centre, kept in the box.
            let radius = settings.jitterRadiusMetres * Double.random(in: 0...1, using: &generator).squareRoot()
            let angle = Double.random(in: 0..<(2 * .pi), using: &generator)
            (targetX, targetY) = area.clamped(x: radius * cos(angle), y: radius * sin(angle))
        }
    }
}
