// Offline check for the location schedule resolver.
// xcrun swiftc -parse-as-library scripts/test-location-schedule.swift \
//   WrapPin/Models/LocationSchedule.swift WrapPin/Models/LocationTarget.swift \
//   -o /tmp/schedule-check && /tmp/schedule-check

import Foundation

@main
struct LocationScheduleCheck {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!

        func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
        }

        let office = LocationTarget(name: "Office", subtitle: "", latitude: 25.04, longitude: 121.56)
        let home = LocationTarget(name: "Home", subtitle: "", latitude: 25.06, longitude: 121.52)
        let morning = ScheduleEntry(hour: 8, minute: 30, weekdays: ScheduleEntry.weekdaysOnly, action: .place(office))
        let evening = ScheduleEntry(hour: 18, minute: 0, weekdays: ScheduleEntry.weekdaysOnly,
                                    action: .route(mode: .walking, destination: home))
        let weekend = ScheduleEntry(hour: 10, minute: 0, weekdays: ScheduleEntry.weekendOnly, action: .restore)
        let entries = [morning, evening, weekend]

        // 2026-11-27 is a Friday.
        precondition(calendar.component(.weekday, from: date(2026, 11, 27, 12, 0)) == 6)

        // Friday noon → the 08:30 office entry.
        var recent = ScheduleResolver.mostRecentOccurrence(in: entries, atOrBefore: date(2026, 11, 27, 12, 0), calendar: calendar)
        precondition(recent?.entryID == morning.id && recent?.date == date(2026, 11, 27, 8, 30))

        // Exactly at the minute it fires.
        recent = ScheduleResolver.mostRecentOccurrence(in: entries, atOrBefore: date(2026, 11, 27, 18, 0), calendar: calendar)
        precondition(recent?.entryID == evening.id)

        // Friday 07:00 → Thursday's 18:00 walk home.
        recent = ScheduleResolver.mostRecentOccurrence(in: entries, atOrBefore: date(2026, 11, 27, 7, 0), calendar: calendar)
        precondition(recent?.entryID == evening.id && recent?.date == date(2026, 11, 26, 18, 0))

        // Sunday 09:00 → Saturday 10:00 restore (weekend entry), not Friday's walk.
        recent = ScheduleResolver.mostRecentOccurrence(in: entries, atOrBefore: date(2026, 11, 29, 9, 0), calendar: calendar)
        precondition(recent?.entryID == weekend.id && recent?.date == date(2026, 11, 28, 10, 0))

        // Next after Friday 18:00 is Saturday 10:00.
        let next = ScheduleResolver.nextOccurrence(in: entries, after: date(2026, 11, 27, 18, 0), calendar: calendar)
        precondition(next?.entryID == weekend.id && next?.date == date(2026, 11, 28, 10, 0))

        // Disabled and empty-weekday entries never fire.
        var disabled = morning
        disabled.isEnabled = false
        let empty = ScheduleEntry(hour: 9, minute: 0, weekdays: [], action: .restore)
        precondition(ScheduleResolver.mostRecentOccurrence(in: [disabled, empty], atOrBefore: date(2026, 11, 27, 12, 0), calendar: calendar) == nil)
        precondition(ScheduleResolver.nextOccurrence(in: [disabled, empty], after: date(2026, 11, 27, 12, 0), calendar: calendar) == nil)

        // Same minute: the later list entry wins.
        let a = ScheduleEntry(hour: 9, minute: 0, action: .place(office))
        let b = ScheduleEntry(hour: 9, minute: 0, action: .place(home))
        recent = ScheduleResolver.mostRecentOccurrence(in: [a, b], atOrBefore: date(2026, 11, 27, 9, 5), calendar: calendar)
        precondition(recent?.entryID == b.id)

        // Due: applies a missed firing once, never twice, and not before the baseline.
        let noon = date(2026, 11, 27, 12, 0)
        let due = ScheduleResolver.dueOccurrence(in: entries, now: noon, lastApplied: nil, baseline: date(2026, 11, 27, 8, 0), calendar: calendar)
        precondition(due?.entryID == morning.id, "missed 08:30 should apply at noon")
        precondition(ScheduleResolver.dueOccurrence(in: entries, now: noon, lastApplied: due, baseline: nil, calendar: calendar) == nil)
        precondition(ScheduleResolver.dueOccurrence(in: entries, now: noon, lastApplied: nil, baseline: date(2026, 11, 27, 9, 0), calendar: calendar) == nil,
                     "edits after 08:30 must not fire it retroactively")

        // Distinct times for automations, sorted.
        let times = ScheduleResolver.distinctTimes(in: entries + [a, b])
        precondition(times.map { $0.hour * 60 + $0.minute } == [8 * 60 + 30, 9 * 60, 10 * 60, 18 * 60])

        // Codable round trip, including every action kind.
        let all = entries + [ScheduleEntry(hour: 7, minute: 5, action: .drift(areaID: UUID(), areaName: "Park")),
                             ScheduleEntry(hour: 7, minute: 6, action: .route(mode: .driving, destination: office))]
        let data = try JSONEncoder().encode(all)
        let decoded = try JSONDecoder().decode([ScheduleEntry].self, from: data)
        precondition(decoded == all)
        precondition(Set(all.map(\.action.kind)) == Set(ScheduledActionKind.allCases))

        // Clamping.
        let clamped = ScheduleEntry(hour: 30, minute: -4, weekdays: [0, 3, 9], action: .restore)
        precondition(clamped.hour == 23 && clamped.minute == 0 && clamped.weekdays == [3])
        precondition(morning.timeText == "08:30")

        print("Location schedule checks passed.")
    }
}
