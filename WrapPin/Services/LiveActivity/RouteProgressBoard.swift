import Foundation

/// The walking/driving simulator lives in the map screen, while the Live
/// Activity is driven from AppModel. This board carries the route's progress
/// between them without coupling the two.
@MainActor
final class RouteProgressBoard {
    static let shared = RouteProgressBoard()

    private(set) var current: WrapPinActivityAttributes.RouteProgress?
    var onChange: ((WrapPinActivityAttributes.RouteProgress?) -> Void)?

    func publish(_ progress: WrapPinActivityAttributes.RouteProgress?) {
        guard progress != current else { return }
        current = progress
        onChange?(progress)
    }

    private(set) var nextSchedule: String?
    var onNextScheduleChange: ((String?) -> Void)?

    func publishNextSchedule(_ text: String?) {
        guard text != nextSchedule else { return }
        nextSchedule = text
        onNextScheduleChange?(text)
    }

    private(set) var currentDrift: WrapPinActivityAttributes.DriftStatus?
    var onDriftChange: ((WrapPinActivityAttributes.DriftStatus?) -> Void)?

    func publishDrift(_ drift: WrapPinActivityAttributes.DriftStatus?) {
        guard drift != currentDrift else { return }
        currentDrift = drift
        onDriftChange?(drift)
    }
}
