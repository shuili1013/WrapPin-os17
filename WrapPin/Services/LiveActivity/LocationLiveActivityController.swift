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

    init() {
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
                startedAt: startedAt ?? Date()
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

    private func show(_ state: State) {
        guard state != lastState else { return }
        lastState = state
        if let activity {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }
        pendingState = state
        startPendingIfNeeded()
    }

    private func startPendingIfNeeded() {
        guard activity == nil, let state = pendingState else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        do {
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
        pendingState = nil
        lastState = nil
        startedAt = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
