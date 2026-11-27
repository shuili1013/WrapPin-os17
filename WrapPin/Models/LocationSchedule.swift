import Foundation

// Location schedule: "at this time on these weekdays, switch to …".
// Foundation-only (plus LocationTarget) so scripts/test-location-schedule.swift
// can compile it on its own.

enum ScheduledAction: Codable, Equatable, Sendable {
    /// Simulate a fixed place.
    case place(LocationTarget)
    /// Drift inside a saved area, using the drift settings saved in WrapPin.
    case drift(areaID: UUID, areaName: String)
    /// Walk or drive from the current position to a place.
    case route(mode: ScheduledRouteMode, destination: LocationTarget)
    /// Stop simulating and restore the real location.
    case restore

    var kind: ScheduledActionKind {
        switch self {
        case .place: .place
        case .drift: .drift
        case .route(let mode, _): mode == .walking ? .walk : .drive
        case .restore: .restore
        }
    }

    /// Place or area name for lists; empty for restore.
    var targetName: String {
        switch self {
        case .place(let target): target.name
        case .drift(_, let name): name
        case .route(_, let destination): destination.name
        case .restore: ""
        }
    }
}

/// Kept separate from RouteMode so this file has no MapKit dependency.
enum ScheduledRouteMode: String, Codable, Sendable {
    case walking
    case driving
}

enum ScheduledActionKind: String, CaseIterable, Identifiable, Sendable {
    case place, drift, walk, drive, restore
    var id: Self { self }
}

struct ScheduleEntry: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var isEnabled: Bool
    /// 0...23
    var hour: Int
    /// 0...59
    var minute: Int
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday. Empty never fires.
    var weekdays: Set<Int>
    var action: ScheduledAction

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        hour: Int,
        minute: Int,
        weekdays: Set<Int> = ScheduleEntry.everyDay,
        action: ScheduledAction
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.weekdays = weekdays.filter { (1...7).contains($0) }
        self.action = action
    }

    static let everyDay: Set<Int> = Set(1...7)
    static let weekdaysOnly: Set<Int> = [2, 3, 4, 5, 6]
    static let weekendOnly: Set<Int> = [1, 7]

    var minutesSinceMidnight: Int { hour * 60 + minute }

    /// "08:30"
    var timeText: String { String(format: "%02d:%02d", hour, minute) }
}

/// One firing of an entry: which entry, at which moment.
struct ScheduleOccurrence: Codable, Equatable, Sendable {
    var entryID: UUID
    var date: Date
}

enum ScheduleResolver {
    /// The latest firing at or before `now` among enabled entries, looking back
    /// a little over a week. Later firings win; at the same minute the entry
    /// that comes later in the list wins, so the list order breaks ties.
    static func mostRecentOccurrence(
        in entries: [ScheduleEntry],
        atOrBefore now: Date,
        calendar: Calendar = .current
    ) -> ScheduleOccurrence? {
        var best: (occurrence: ScheduleOccurrence, order: Int)?
        for (order, entry) in entries.enumerated() where entry.isEnabled && !entry.weekdays.isEmpty {
            for dayOffset in 0...7 {
                guard
                    let day = calendar.date(byAdding: .day, value: -dayOffset, to: now),
                    let date = firing(of: entry, on: day, calendar: calendar),
                    date <= now
                else { continue }
                if let current = best,
                   current.occurrence.date > date || (current.occurrence.date == date && current.order > order) {
                    break
                }
                best = (ScheduleOccurrence(entryID: entry.id, date: date), order)
                break
            }
        }
        return best?.occurrence
    }

    /// The first firing strictly after `now`.
    static func nextOccurrence(
        in entries: [ScheduleEntry],
        after now: Date,
        calendar: Calendar = .current
    ) -> ScheduleOccurrence? {
        var best: ScheduleOccurrence?
        for entry in entries where entry.isEnabled && !entry.weekdays.isEmpty {
            for dayOffset in 0...7 {
                guard
                    let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
                    let date = firing(of: entry, on: day, calendar: calendar),
                    date > now
                else { continue }
                if best == nil || date < best!.date {
                    best = ScheduleOccurrence(entryID: entry.id, date: date)
                }
                break
            }
        }
        return best
    }

    /// The occurrence that should be applied now, or nil when nothing new is due.
    /// Firings at or before `baseline` (when the schedule was last edited or
    /// switched on) are not applied retroactively; anything missed after that
    /// is applied as soon as WrapPin runs.
    static func dueOccurrence(
        in entries: [ScheduleEntry],
        now: Date,
        lastApplied: ScheduleOccurrence?,
        baseline: Date?,
        calendar: Calendar = .current
    ) -> ScheduleOccurrence? {
        guard let occurrence = mostRecentOccurrence(in: entries, atOrBefore: now, calendar: calendar) else {
            return nil
        }
        if let baseline, occurrence.date <= baseline { return nil }
        if occurrence == lastApplied { return nil }
        return occurrence
    }

    /// Distinct firing times, for setting up Shortcuts automations.
    static func distinctTimes(in entries: [ScheduleEntry]) -> [(hour: Int, minute: Int)] {
        let minutes = Set(entries.filter { $0.isEnabled && !$0.weekdays.isEmpty }.map(\.minutesSinceMidnight))
        return minutes.sorted().map { ($0 / 60, $0 % 60) }
    }

    private static func firing(of entry: ScheduleEntry, on day: Date, calendar: Calendar) -> Date? {
        guard entry.weekdays.contains(calendar.component(.weekday, from: day)) else { return nil }
        return calendar.date(bySettingHour: entry.hour, minute: entry.minute, second: 0, of: day)
    }
}
