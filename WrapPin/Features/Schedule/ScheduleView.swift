import SwiftUI

/// The location schedule page: switch it on, list steps, add and edit them,
/// and set up the Shortcuts automations that wake WrapPin.
struct ScheduleView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The place selected on the map, offered as a quick target.
    let currentSelection: LocationTarget?

    @State private var editing: ScheduleEntry?
    @State private var isAdding = false
    @State private var isShowingAutomationGuide = false
    @State private var isShowingKeepAliveGuide = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(
                        get: { appModel.isScheduleEnabled },
                        set: { enabled in
                            withAnimation(reduceMotion ? nil : MapAnimation.snappy) {
                                appModel.setScheduleEnabled(enabled)
                            }
                        }
                    )) {
                        Label("Use Location Schedule", systemImage: "calendar.badge.clock")
                    }
                    .tint(.purple)

                    if appModel.isScheduleEnabled, let next = nextText {
                        LabeledContent {
                            Text(verbatim: next)
                                .foregroundStyle(.purple)
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Text("Next")
                        }
                        .transition(.opacity)
                    }
                } footer: {
                    Text("While a simulation is running, WrapPin switches on time by itself. To switch while WrapPin is closed or asleep, add a Shortcuts automation for each time.")
                }

                Section {
                    if appModel.scheduleEntries.isEmpty {
                        ContentUnavailableView {
                            Label("No Schedule Yet", systemImage: "calendar")
                        } description: {
                            Text("Add a time and choose where this iPhone should be.")
                        } actions: {
                            Button("Add Step") { isAdding = true }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                        }
                    } else {
                        ForEach(appModel.scheduleEntries) { entry in
                            Button {
                                editing = entry
                            } label: {
                                ScheduleRow(entry: entry, label: appModel.scheduleLabel(for: entry))
                            }
                            .buttonStyle(.pressable)
                            .swipeActions(edge: .leading) {
                                Button {
                                    appModel.setScheduleEntry(id: entry.id, enabled: !entry.isEnabled)
                                } label: {
                                    if entry.isEnabled {
                                        Label("Turn Off", systemImage: "pause")
                                    } else {
                                        Label("Turn On", systemImage: "play")
                                    }
                                }
                                .tint(entry.isEnabled ? .gray : .purple)
                            }
                        }
                        .onDelete { offsets in
                            let ids = Set(offsets.map { appModel.scheduleEntries[$0].id })
                            withAnimation { appModel.deleteScheduleEntries(withIDs: ids) }
                        }
                    }
                } header: {
                    Text("Steps")
                } footer: {
                    if !appModel.scheduleEntries.isEmpty {
                        Text("If WrapPin was asleep at a step's time, the step is applied as soon as WrapPin runs again. Swipe right to pause a step, left to delete it.")
                    }
                }

                Section {
                    Button {
                        isShowingAutomationGuide = true
                    } label: {
                        Label("Set Up Schedule Automations", systemImage: "wand.and.stars")
                    }
                    Button {
                        isShowingKeepAliveGuide = true
                    } label: {
                        Label("Keep Alive with Shortcuts", systemImage: "bolt.heart")
                    }
                } header: {
                    Text("Shortcuts")
                }
            }
            .animation(reduceMotion ? nil : MapAnimation.snappy, value: appModel.scheduleEntries)
            .navigationTitle("Location Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isAdding = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Step")
                }
            }
            .sheet(isPresented: $isAdding) {
                ScheduleEntryEditor(entry: nil, currentSelection: currentSelection) { saved in
                    save(saved)
                }
                .environment(appModel)
            }
            .sheet(item: $editing) { entry in
                ScheduleEntryEditor(entry: entry, currentSelection: currentSelection) { saved in
                    save(saved)
                }
                .environment(appModel)
            }
            .sheet(isPresented: $isShowingAutomationGuide) {
                ScheduleAutomationGuideView()
                    .environment(appModel)
            }
            .sheet(isPresented: $isShowingKeepAliveGuide) {
                KeepAliveGuideView()
            }
        }
    }

    private var nextText: String? {
        guard
            let next = appModel.nextScheduleOccurrence(),
            let entry = appModel.scheduleEntry(withID: next.entryID)
        else { return nil }
        let label = appModel.scheduleLabel(for: entry)
        if Calendar.current.isDateInToday(next.date) { return label }
        return "\(next.date.formatted(.dateTime.weekday(.abbreviated))) \(label)"
    }

    /// Saving switches the schedule on and walks through adding automations.
    private func save(_ entry: ScheduleEntry) {
        withAnimation(reduceMotion ? nil : MapAnimation.snappy) {
            appModel.saveScheduleEntry(entry)
            if !appModel.isScheduleEnabled { appModel.setScheduleEnabled(true) }
        }
        // Let the editor sheet finish dismissing first.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            isShowingAutomationGuide = true
        }
    }
}

private struct ScheduleRow: View {
    let entry: ScheduleEntry
    let label: String

    var body: some View {
        HStack(spacing: 14) {
            Text(verbatim: entry.timeText)
                .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(entry.isEnabled ? .primary : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Label {
                    Text(verbatim: actionText)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: ScheduleUI.symbol(for: entry.action.kind))
                        .foregroundStyle(entry.isEnabled ? .purple : .secondary)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(entry.isEnabled ? .primary : .secondary)

                Text(verbatim: ScheduleUI.weekdayText(entry.weekdays))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if !entry.isEnabled {
                Text("Off")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// The label without its leading time.
    private var actionText: String {
        let prefix = entry.timeText + " → "
        return label.hasPrefix(prefix) ? String(label.dropFirst(prefix.count)) : label
    }
}

enum ScheduleUI {
    static func symbol(for kind: ScheduledActionKind) -> String {
        switch kind {
        case .place: "mappin.circle.fill"
        case .drift: "square.dashed"
        case .walk: "figure.walk"
        case .drive: "car.fill"
        case .restore: "location.slash.fill"
        }
    }

    static func title(for kind: ScheduledActionKind) -> String {
        switch kind {
        case .place: String(localized: "Go to a place")
        case .drift: String(localized: "Drift in an area")
        case .walk: String(localized: "Walk to a place")
        case .drive: String(localized: "Drive to a place")
        case .restore: String(localized: "Restore real location")
        }
    }

    /// "Every day", "Weekdays", "Weekends" or "Mon, Wed, Fri".
    static func weekdayText(_ days: Set<Int>) -> String {
        if days == ScheduleEntry.everyDay { return String(localized: "Every day") }
        if days == ScheduleEntry.weekdaysOnly { return String(localized: "Weekdays") }
        if days == ScheduleEntry.weekendOnly { return String(localized: "Weekends") }
        if days.isEmpty { return String(localized: "Never") }
        let symbols = Calendar.current.shortWeekdaySymbols
        return orderedWeekdays.filter(days.contains).map { symbols[$0 - 1] }.joined(separator: ", ")
    }

    /// Weekdays in the order this locale shows them.
    static var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }
}
