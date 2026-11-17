import CoreLocation
import Foundation
import Observation

enum AreaDriftPhase: Equatable {
    case idle
    case preparing
    case running
    case paused
    case stopping
    case failed(String)
}

/// Keeps the simulated location moving inside a `DriftArea`. Each second it
/// advances a `DriftEngine` and sends the new point through the existing
/// session with `updateLocation`, like the route simulator does, so the native
/// connection is never rebuilt.
@MainActor
@Observable
final class AreaDriftController {
    private(set) var phase: AreaDriftPhase = .idle {
        didSet {
            if phase != oldValue { publishLiveActivityStatus() }
        }
    }
    private(set) var area: DriftArea?
    private(set) var currentCoordinate: CLLocationCoordinate2D?
    private(set) var settings = DriftSettings()

    @ObservationIgnored private var engine: DriftEngine?
    @ObservationIgnored private var generator = SystemRandomNumberGenerator()
    @ObservationIgnored private var movementTask: Task<Void, Never>?
    @ObservationIgnored private var coordinateMode: FixedCoordinateMode = .wgs84

    /// True from start until the session is stopped; the map uses it to lock
    /// other simulations.
    var isRunning: Bool {
        switch phase {
        case .preparing, .running, .paused, .stopping: true
        case .idle, .failed: false
        }
    }

    var isPausedAtWaypoint: Bool { engine?.isPausedAtWaypoint ?? false }

    func start(
        area: DriftArea,
        settings: DriftSettings,
        coordinateMode: FixedCoordinateMode,
        using appModel: AppModel
    ) async {
        guard !isRunning else { return }
        guard case .paired = appModel.pairingStatus else {
            phase = .failed(String(localized: "Pair this iPhone before starting area drift."))
            return
        }

        movementTask?.cancel()
        self.area = area
        self.settings = settings.sanitised()
        self.coordinateMode = coordinateMode
        var engine = DriftEngine(area: area, settings: self.settings, using: &generator)
        let first = engine.step(elapsed: 0, using: &generator)
        self.engine = engine
        currentCoordinate = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
        let target = driftTarget(at: first)

        // Already simulating: keep the connection and begin moving at once.
        if case .active = appModel.deviceSession.phase {
            phase = .running
            guard send(target, through: appModel.deviceSession) else { return }
            beginMovement(using: appModel.deviceSession)
            return
        }

        phase = .preparing
        await appModel.startLocationSession(at: target, coordinateMode: coordinateMode)
        if case .idle = appModel.deviceSession.phase, phase == .preparing {
            phase = .failed(String(localized: "WrapPin could not start area drift."))
        }
    }

    /// Applies new speed, interval or mode while running.
    func updateSettings(_ settings: DriftSettings) {
        self.settings = settings.sanitised()
        engine?.updateSettings(self.settings, using: &generator)
        publishLiveActivityStatus()
    }

    func togglePause() {
        switch phase {
        case .running: phase = .paused
        case .paused: phase = .running
        case .idle, .preparing, .stopping, .failed: break
        }
    }

    /// Stops drifting but leaves the iPhone at the current drifted point.
    func stopDrifting() {
        movementTask?.cancel()
        movementTask = nil
        engine = nil
        phase = .idle
    }

    /// Stops drifting and the whole location session (restores real location).
    func stop(using deviceSession: LocalDeviceSessionCoordinator) {
        guard isRunning || isFailed else { return }
        movementTask?.cancel()
        movementTask = nil
        if case .idle = deviceSession.phase {
            reset()
            return
        }
        phase = .stopping
        deviceSession.stop()
    }

    func handleDeviceSessionPhase(
        _ devicePhase: DeviceSessionPhase,
        deviceSession: LocalDeviceSessionCoordinator
    ) {
        switch devicePhase {
        case .active:
            guard phase == .preparing else { return }
            phase = .running
            beginMovement(using: deviceSession)
        case .stopping:
            if isRunning {
                movementTask?.cancel()
                movementTask = nil
                phase = .stopping
            }
        case .idle:
            guard isRunning else { return }
            reset()
        case .failed(let message):
            guard isRunning else { return }
            movementTask?.cancel()
            movementTask = nil
            engine = nil
            phase = .failed(message)
        case .openingLocalDevVPN, .discovering, .connecting:
            break
        }
    }

    func reset() {
        movementTask?.cancel()
        movementTask = nil
        engine = nil
        currentCoordinate = nil
        area = nil
        phase = .idle
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func beginMovement(using deviceSession: LocalDeviceSessionCoordinator) {
        movementTask?.cancel()
        movementTask = Task { @MainActor [weak self, weak deviceSession] in
            var lastTick = Date.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, let deviceSession else { return }
                let now = Date.now
                let elapsed = now.timeIntervalSince(lastTick)
                lastTick = now

                if self.phase == .paused { continue }
                // Hold position while the device channel is rebuilt.
                if deviceSession.isReconnecting { continue }
                guard self.phase == .running, var engine = self.engine else { return }

                let point = engine.step(elapsed: elapsed, using: &self.generator)
                self.engine = engine
                self.currentCoordinate = CLLocationCoordinate2D(
                    latitude: point.latitude,
                    longitude: point.longitude
                )
                guard self.send(self.driftTarget(at: point), through: deviceSession) else { return }
            }
        }
    }

    @discardableResult
    private func send(_ target: LocationTarget, through deviceSession: LocalDeviceSessionCoordinator) -> Bool {
        let coordinates = FixedCoordinateTransform.coordinates(for: target, mode: coordinateMode)
        guard deviceSession.updateLocation(target, simulationCoordinates: coordinates) == .updated else {
            movementTask?.cancel()
            movementTask = nil
            engine = nil
            phase = .failed(String(localized: "The active location session ended while drifting."))
            return false
        }
        return true
    }

    private func driftTarget(at point: (latitude: Double, longitude: Double)) -> LocationTarget {
        LocationTarget(
            name: area?.name ?? String(localized: "Area Drift"),
            subtitle: String(localized: "Drifting inside the area"),
            latitude: point.latitude,
            longitude: point.longitude
        )
    }

    private func publishLiveActivityStatus() {
        guard let area, phase == .running || phase == .paused || phase == .preparing else {
            RouteProgressBoard.shared.publishDrift(nil)
            return
        }
        let kind: WrapPinActivityAttributes.DriftKind = switch settings.mode {
        case .wander: .wander
        case .jump: .jump
        case .jitter: .jitter
        }
        RouteProgressBoard.shared.publishDrift(WrapPinActivityAttributes.DriftStatus(
            areaName: area.name,
            kind: kind,
            isPaused: phase == .paused
        ))
    }
}
