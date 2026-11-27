// Shared between the app and the WrapPinLiveActivity widget extension.
// The two copies must stay byte-for-byte identical (CI checks this):
//   WrapPin/Services/LiveActivity/WrapPinActivityAttributes.swift
//   WrapPinLiveActivity/WrapPinActivityAttributes.swift
// ActivityKit matches the type by name, so do not rename it.

import ActivityKit
import Foundation

struct WrapPinActivityAttributes: ActivityAttributes {
    enum Status: String, Codable, Hashable {
        case active
        case reconnecting
    }

    enum RouteKind: String, Codable, Hashable {
        case walking
        case driving
    }

    /// Present only while a walking or driving route is being simulated.
    struct RouteProgress: Codable, Hashable {
        var kind: RouteKind
        var destinationName: String
        /// 0...1
        var progress: Double
        /// Estimated arrival; nil while paused or after arriving, so the
        /// countdown never runs while the walker is not moving.
        var arrivesAt: Date?
        var isPaused: Bool
        var hasArrived: Bool
    }

    enum DriftKind: String, Codable, Hashable {
        case wander
        case jump
        case jitter
    }

    /// Present only while area drift is running.
    struct DriftStatus: Codable, Hashable {
        var areaName: String
        var kind: DriftKind
        var isPaused: Bool
    }

    struct ContentState: Codable, Hashable {
        var placeName: String
        var subtitle: String
        var latitude: Double
        var longitude: Double
        var status: Status
        var startedAt: Date
        var route: RouteProgress?
        var drift: DriftStatus?
        /// "08:30 → Office", when a location schedule is on.
        var nextSchedule: String?
    }

    /// Identifies one location session; not shown to the user.
    var sessionID: String
}
