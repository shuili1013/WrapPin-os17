import SwiftUI

/// iOS does not let apps create automations, so after saving a schedule this
/// walks through adding one "Time of Day" automation per schedule time.
struct ScheduleAutomationGuideView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("iOS only lets you create automations yourself, in the Shortcuts app. Add one automation for each time below; each takes about 30 seconds and is done once.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if times.isEmpty {
                    Section {
                        Text("Add a step to the schedule first.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(times, id: \.minutes) { time in
                            HStack(spacing: 14) {
                                Text(verbatim: time.text)
                                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                                Text(verbatim: ScheduleUI.weekdayText(time.weekdays))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Times to add")
                    }
                }

                Section {
                    GuideStep(number: 1, text: String(localized: "Open the Shortcuts app and go to the Automation tab."))
                    GuideStep(number: 2, text: String(localized: "Tap + (or New Automation), then choose Time of Day."))
                    GuideStep(number: 3, text: String(localized: "Set the time to one of the times above, choose Weekly and the same days, then choose Run Immediately."))
                    GuideStep(number: 4, text: String(localized: "Tap Next, search for WrapPin and choose Run WrapPin Schedule."))
                    GuideStep(number: 5, text: String(localized: "Tap Done. Repeat for each time."))
                } header: {
                    Text("Steps")
                } footer: {
                    Text("Keep LocalDevVPN connected so WrapPin can switch right away. After restarting the iPhone, open WrapPin once.")
                }

                Section {
                    Button {
                        if let url = URL(string: "shortcuts://") { openURL(url) }
                    } label: {
                        Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Schedule Automations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private struct GuideTime {
        let minutes: Int
        let weekdays: Set<Int>
        var text: String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    }

    /// Each distinct time with the union of its weekdays.
    private var times: [GuideTime] {
        ScheduleResolver.distinctTimes(in: appModel.scheduleEntries).map { time in
            let minutes = time.hour * 60 + time.minute
            let days = appModel.scheduleEntries
                .filter { $0.isEnabled && $0.minutesSinceMidnight == minutes }
                .reduce(into: Set<Int>()) { $0.formUnion($1.weekdays) }
            return GuideTime(minutes: minutes, weekdays: days)
        }
    }
}

/// Two ways to keep WrapPin running with Shortcuts automations.
struct KeepAliveGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("iOS can stop WrapPin in the background. Keep WrapPin Alive opens WrapPin, reconnects, resumes an interrupted simulation and applies any schedule step that is due. Use one or both automations below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    GuideStep(number: 1, text: String(localized: "In Shortcuts, open Automation and tap +, then choose Time of Day."))
                    GuideStep(number: 2, text: String(localized: "Pick a time, choose Daily and Run Immediately, then tap Next."))
                    GuideStep(number: 3, text: String(localized: "Search for WrapPin, choose Keep WrapPin Alive and tap Done."))
                    GuideStep(number: 4, text: String(localized: "Repeat for more times (for example every hour you need it)."))
                } header: {
                    Label("Wake WrapPin at set times", systemImage: "clock.arrow.circlepath")
                } footer: {
                    Text("Each run brings WrapPin to the front for a moment.")
                }

                Section {
                    GuideStep(number: 1, text: String(localized: "In Shortcuts, open Automation and tap +, then choose App."))
                    GuideStep(number: 2, text: String(localized: "Choose WrapPin, select Is Closed (and deselect Is Opened), choose Run Immediately, then tap Next."))
                    GuideStep(number: 3, text: String(localized: "Search for WrapPin, choose Keep WrapPin Alive and tap Done."))
                } header: {
                    Label("Reopen WrapPin when it closes", systemImage: "arrow.uturn.backward.circle")
                } footer: {
                    Text("The most reliable option: if WrapPin is swiped away or closed, it opens again and carries on. Turn the automation off when you do not need it.")
                }

                Section {
                    Text("A restart always ends the simulation. LocalDevVPN must stay connected. With a free Apple ID, refresh WrapPin in SideStore every 7 days.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Limits")
                }

                Section {
                    Button {
                        if let url = URL(string: "shortcuts://") { openURL(url) }
                    } label: {
                        Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Keep Alive with Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct GuideStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.purple, in: Circle())
            Text(verbatim: text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
