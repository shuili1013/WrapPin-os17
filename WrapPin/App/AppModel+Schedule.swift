import Foundation

/// A schedule step or keep-alive check asked for by a Shortcuts action.
/// AppModel checks preconditions; HomeView performs it with the same code as
/// the in-app schedule, which needs the map, route and drift controllers.
struct ScheduleRunRequest: Equatable {
    enum Reason: Equatable {
        /// "Run WrapPin Schedule": apply the step for the current time.
        case runSchedule
        /// "Keep WrapPin Alive": reconnect or resume, then apply the schedule.
        case keepAlive
    }

    let id = UUID()
    let reason: Reason
}

enum KeepAliveOutcome {
    case alreadyRunning
    case resuming
    case applyingSchedule(String)
    case nothingToKeep
}

enum ScheduleRunOutcome {
    case applying(String)
    case alreadyApplied(String)
    case nothingScheduled
}

enum ScheduleShortcutFailure: Error, CustomLocalizedStringResourceConvertible {
    case scheduleOff

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .scheduleOff:
            LocalizedStringResource("The location schedule is switched off. Turn it on in WrapPin first.")
        }
    }
}

extension AppModel {
    /// Hands the current schedule step to HomeView.
    func requestScheduleRun() async throws -> ScheduleRunOutcome {
        try await waitForScheduleShortcutReadiness()
        guard isScheduleEnabled else { throw ScheduleShortcutFailure.scheduleOff }
        guard
            let occurrence = currentScheduleOccurrence(),
            let entry = scheduleEntry(withID: occurrence.entryID)
        else { return .nothingScheduled }

        let label = scheduleLabel(for: entry)
        if occurrence == lastAppliedScheduleOccurrence, isSimulationLive {
            return .alreadyApplied(label)
        }
        scheduleRunRequest = ScheduleRunRequest(reason: .runSchedule)
        return .applying(label)
    }

    /// Wakes WrapPin from an automation and makes sure the simulation carries on.
    func requestKeepAlive() async throws -> KeepAliveOutcome {
        try await waitForScheduleShortcutReadiness()
        let due = dueScheduleOccurrence().flatMap { scheduleEntry(withID: $0.entryID) }
        let needsResume = !isSimulationLive && (interruptedSession != nil || currentScheduleOccurrence() != nil)
        guard due != nil || needsResume else {
            return isSimulationLive ? .alreadyRunning : .nothingToKeep
        }
        scheduleRunRequest = ScheduleRunRequest(reason: .keepAlive)
        if let due { return .applyingSchedule(scheduleLabel(for: due)) }
        return .resuming
    }

    func takeScheduleRunRequest() -> ScheduleRunRequest? {
        defer { scheduleRunRequest = nil }
        return scheduleRunRequest
    }

    /// "08:30 → Office" style text for dialogs and the map.
    func scheduleLabel(for entry: ScheduleEntry) -> String {
        let target = entry.action.targetName
        switch entry.action.kind {
        case .restore:
            return String(format: NSLocalizedString("%@ → Restore real location", comment: ""), entry.timeText)
        case .walk:
            return String(format: NSLocalizedString("%@ → Walk to %@", comment: ""), entry.timeText, target)
        case .drive:
            return String(format: NSLocalizedString("%@ → Drive to %@", comment: ""), entry.timeText, target)
        case .drift:
            return String(format: NSLocalizedString("%@ → Drift in %@", comment: ""), entry.timeText, target)
        case .place:
            return String(format: NSLocalizedString("%@ → %@", comment: ""), entry.timeText, target)
        }
    }

    var isSimulationLive: Bool {
        if isStartingLocationSession { return true }
        switch deviceSession.phase {
        case .idle, .failed: return false
        case .openingLocalDevVPN, .discovering, .connecting, .active, .stopping: return true
        }
    }

    private func waitForScheduleShortcutReadiness() async throws {
        guard hasCompletedOnboarding else { throw ShortcutFailure.notSetUp }
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            switch pairingStatus {
            case .checking, .importing:
                try? await Task.sleep(for: .milliseconds(200))
                continue
            case .paired, .notPaired, .failed:
                break
            }
            break
        }
        guard case .paired = pairingStatus else { throw ShortcutFailure.notPaired }
    }
}
