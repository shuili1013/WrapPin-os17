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
}
