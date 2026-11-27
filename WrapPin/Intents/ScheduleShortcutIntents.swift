import AppIntents

// Both open WrapPin: a step may need to start a session, which can hand off
// to the tunnel app, and the map screen performs the step.

/// Use from a Shortcuts "Time of Day" automation at each schedule time.
struct RunLocationScheduleIntent: AppIntent {
    static let title: LocalizedStringResource = "Run WrapPin Schedule"
    static let description = IntentDescription("Opens WrapPin and applies the location schedule step for the current time.")
    static let openAppWhenRun = true

    @available(iOS 26, *)
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Dependency private var appModel: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch try await appModel.requestScheduleRun() {
        case .applying(let label):
            return .result(dialog: "Applying \(label).")
        case .alreadyApplied(let label):
            return .result(dialog: "Already following \(label).")
        case .nothingScheduled:
            return .result(dialog: IntentDialog(LocalizedStringResource("No schedule step is due yet.")))
        }
    }
}

/// Use from automations (every hour, or when WrapPin is closed) to keep the
/// simulation going.
struct KeepWrapPinAliveIntent: AppIntent {
    static let title: LocalizedStringResource = "Keep WrapPin Alive"
    static let description = IntentDescription("Opens WrapPin, reconnects or resumes an interrupted simulation, and applies any schedule step that is due.")
    static let openAppWhenRun = true

    @available(iOS 26, *)
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Dependency private var appModel: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch try await appModel.requestKeepAlive() {
        case .alreadyRunning:
            return .result(dialog: IntentDialog(LocalizedStringResource("WrapPin is running.")))
        case .resuming:
            return .result(dialog: IntentDialog(LocalizedStringResource("Resuming the simulation.")))
        case .applyingSchedule(let label):
            return .result(dialog: "Applying \(label).")
        case .nothingToKeep:
            return .result(dialog: IntentDialog(LocalizedStringResource("No simulation to keep alive.")))
        }
    }
}
