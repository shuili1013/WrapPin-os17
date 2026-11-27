import ActivityKit
import Foundation
import UIKit

/// Mirrors an active location session on the Lock Screen and in the Dynamic
/// Island. Updates are local (no push token); the app is kept running in the
/// background by the session's location keep-alive, so it can update and end
/// the activity itself. A Live Activity can only be started while WrapPin is
/// in the foreground, so a start requested in the background is retried when
/// the app becomes active again.
@MainActor
final class LocationLiveActivityController {
    private typealias State = WrapPinActivityAttributes.ContentState

    private var activity: Activity<WrapPinActivityAttributes>?
    private var startedAt: Date?
    private var lastState: State?
    private var pendingState: State?
    private var becameActiveObserver: NSObjectProtocol?
    private var lastPushDate = Date.distantPast
    private var deferredState: State?
    private var deferredPushTask: Task<Void, Never>?
    /// iOS budgets Live Activity updates; routine route ticks go out at most this often.
    private let minimumRoutineInterval: TimeInterval = 3

    init() {
        RouteProgressBoard.shared.onChange = { [weak self] route in
            self?.routeProgressChanged(route)
        }
        RouteProgressBoard.shared.onNextScheduleChange = { [weak self] text in
            guard let self, var state = self.lastState else { return }
            state.nextSchedule = text
            self.show(state)
        }
        RouteProgressBoard.shared.onDriftChange = { [weak self] drift in
            guard let self, var state = self.lastState else { return }
            state.drift = drift
            self.show(state)
        }
        // A crash or force-quit can leave an activity from an earlier run.
        Task {
            for stale in Activity<WrapPinActivityAttributes>.activities {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
        }
        becameActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.startPendingIfNeeded() }
        }
    }

    func apply(_ phase: DeviceSessionPhase) {
        switch phase {
        case .active(let target):
            if startedAt == nil { startedAt = Date() }
            show(State(
                placeName: target.name,
                subtitle: target.subtitle,
                latitude: target.latitude,
                longitude: target.longitude,
                status: .active,
                startedAt: startedAt ?? Date(),
                route: RouteProgressBoard.shared.current,
                drift: RouteProgressBoard.shared.currentDrift,
                nextSchedule: RouteProgressBoard.shared.nextSchedule
            ))
        case .openingLocalDevVPN, .discovering, .connecting:
            // Only an already-running session shows reconnecting.
            guard var state = lastState else { return }
            state.status = .reconnecting
            show(state)
        case .stopping, .idle, .failed:
            end()
        }
    }

    private func routeProgressChanged(_ route: WrapPinActivityAttributes.RouteProgress?) {
        guard var state = lastState else { return }
        state.route = route
        show(state)
    }

    private func show(_ state: State) {
        guard state != lastState else { return }
        let previous = lastState
        lastState = state
        guard let activity else {
            pendingState = state
            startPendingIfNeeded()
            return
        }

        // Status, pause/arrival and a new place go out at once; position and
        // progress ticks are coalesced.
        let isImportant = previous == nil
            || previous?.status != state.status
            || (previous?.placeName != state.placeName && previous?.route == nil && state.drift == nil)
            || previous?.route?.isPaused != state.route?.isPaused
            || previous?.route?.hasArrived != state.route?.hasArrived
            || previous?.drift != state.drift
            || previous?.nextSchedule != state.nextSchedule
            || (previous?.route == nil) != (state.route == nil)
        let elapsed = Date().timeIntervalSince(lastPushDate)
        if isImportant || elapsed >= minimumRoutineInterval {
            push(state, to: activity)
        } else {
            deferredState = state
            guard deferredPushTask == nil else { return }
            let delay = minimumRoutineInterval - elapsed
            deferredPushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled else { return }
                self.deferredPushTask = nil
                if let deferred = self.deferredState, let activity = self.activity {
                    self.push(deferred, to: activity)
                }
            }
        }
    }

    private func push(_ state: State, to activity: Activity<WrapPinActivityAttributes>) {
        deferredState = nil
        deferredPushTask?.cancel()
        deferredPushTask = nil
        lastPushDate = Date()
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    private func startPendingIfNeeded() {
        guard activity == nil, let state = pendingState else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        do {
            lastPushDate = Date()
            activity = try Activity.request(
                attributes: WrapPinActivityAttributes(sessionID: UUID().uuidString),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            pendingState = nil
        } catch {
            // Disabled in Settings or the system limit was reached; the app
            // still works without it.
        }
    }

    private func end() {
        deferredPushTask?.cancel()
        deferredPushTask = nil
        deferredState = nil
        pendingState = nil
        lastState = nil
        startedAt = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
