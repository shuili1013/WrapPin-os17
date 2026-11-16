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

    struct ContentState: Codable, Hashable {
        var placeName: String
        var subtitle: String
        var latitude: Double
        var longitude: Double
        var status: Status
        var startedAt: Date
    }

    /// Identifies one location session; not shown to the user.
    var sessionID: String
}
