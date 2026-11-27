import SwiftUI

/// Adds or edits one schedule step: time, weekdays, what to do and where.
struct ScheduleEntryEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let entry: ScheduleEntry?
    let currentSelection: LocationTarget?
    let onSave: (ScheduleEntry) -> Void

    @State private var time: Date
    @State private var weekdays: Set<Int>
    @State private var kind: ScheduledActionKind
    @State private var target: LocationTarget?
    @State private var areaID: UUID?
    @State private var coordinateText = ""
    @State private var coordinateError: String?

    init(entry: ScheduleEntry?, currentSelection: LocationTarget?, onSave: @escaping (ScheduleEntry) -> Void) {
        self.entry = entry
        self.currentSelection = currentSelection
        self.onSave = onSave
        let calendar = Calendar.current
        let now = Date()
        let startTime = entry.flatMap {
            calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: now)
        } ?? calendar.date(bySettingHour: calendar.component(.hour, from: now) + 1, minute: 0, second: 0, of: now)
            ?? now
        _time = State(initialValue: startTime)
        _weekdays = State(initialValue: entry?.weekdays ?? ScheduleEntry.everyDay)
        _kind = State(initialValue: entry?.action.kind ?? .place)
        switch entry?.action {
        case .place(let place):
            _target = State(initialValue: place)
        case .route(_, let destination):
            _target = State(initialValue: destination)
        case .drift(let id, _):
            _areaID = State(initialValue: id)
        case .restore, nil:
            _target = State(initialValue: currentSelection)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }

                Section {
                    weekdayPicker
                    HStack(spacing: 8) {
                        presetButton(String(localized: "Every day"), days: ScheduleEntry.everyDay)
                        presetButton(String(localized: "Weekdays"), days: ScheduleEntry.weekdaysOnly)
                        presetButton(String(localized: "Weekends"), days: ScheduleEntry.weekendOnly)
                    }
                } header: {
                    Text("Repeat")
                }

                Section {
                    Picker("Action", selection: $kind.animation(reduceMotion ? nil : MapAnimation.snappy)) {
                        ForEach(ScheduledActionKind.allCases) { kind in
                            Label {
                                Text(verbatim: ScheduleUI.title(for: kind))
                            } icon: {
                                Image(systemName: ScheduleUI.symbol(for: kind))
                            }
                            .tag(kind)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Action")
                }

                targetSections
            }
            .navigationTitle(entry == nil ? String(localized: "Add Step") : String(localized: "Edit Step"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let saved = builtEntry else { return }
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(builtEntry == nil)
                }
            }
        }
    }

    // MARK: Weekdays

    private var weekdayPicker: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return HStack(spacing: 6) {
            ForEach(ScheduleUI.orderedWeekdays, id: \.self) { day in
                let isOn = weekdays.contains(day)
                Button {
                    withAnimation(reduceMotion ? nil : MapAnimation.snappy) {
                        if isOn { weekdays.remove(day) } else { weekdays.insert(day) }
                    }
                } label: {
                    Text(verbatim: symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(isOn ? .white : .primary)
                        .background(isOn ? Color.purple : Color.secondary.opacity(0.15), in: Circle())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.vertical, 4)
    }

    private func presetButton(_ title: String, days: Set<Int>) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : MapAnimation.snappy) { weekdays = days }
        } label: {
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(weekdays == days ? .purple : .secondary)
    }

    // MARK: Target

    @ViewBuilder
    private var targetSections: some View {
        switch kind {
        case .place, .walk, .drive:
            placeSections
        case .drift:
            areaSection
        case .restore:
            Section {
                Text("Stops the simulation and returns this iPhone to its real location.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var placeSections: some View {
        Section {
            if let target {
                placeRow(target, selected: true)
            } else {
                Text("Choose a place below.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(kind == .place ? String(localized: "Place") : String(localized: "Destination"))
        } footer: {
            if kind == .walk || kind == .drive {
                Text("The route starts from wherever this iPhone appears to be at that time.")
            }
        }

        if let currentSelection, currentSelection != target {
            Section {
                choice(currentSelection)
            } header: {
                Text("Selected on the Map")
            }
        }

        if !appModel.favouriteLocations.isEmpty {
            Section {
                ForEach(appModel.favouriteLocations) { place in
                    choice(place)
                }
            } header: {
                Text("Favourites")
            }
        }

        let recent = appModel.locationHistory.filter { place in
            !appModel.favouriteLocations.contains(place) && place != currentSelection
        }.prefix(8)
        if !recent.isEmpty {
            Section {
                ForEach(Array(recent)) { place in
                    choice(place)
                }
            } header: {
                Text("Recent")
            }
        }

        Section {
            HStack {
                TextField("25.0330, 121.5654", text: $coordinateText)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Use") { useCoordinates() }
                    .disabled(coordinateText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let coordinateError {
                Text(verbatim: coordinateError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Coordinates")
        }
    }

    private var areaSection: some View {
        Section {
            if appModel.savedDriftAreas.isEmpty {
                Text("No saved areas yet. Draw a box with Area Drift on the map and save it first.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appModel.savedDriftAreas) { area in
                    Button {
                        withAnimation(reduceMotion ? nil : MapAnimation.snappy) { areaID = area.id }
                    } label: {
                        HStack {
                            Image(systemName: areaID == area.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(.purple)
                                .contentTransition(.symbolEffect(.replace))
                            Text(verbatim: area.name)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
            }
        } header: {
            Text("Saved Areas")
        } footer: {
            Text("Uses the drift style and speed currently set in Area Drift.")
        }
    }

    private func choice(_ place: LocationTarget) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : MapAnimation.snappy) { target = place }
        } label: {
            placeRow(place, selected: false)
        }
        .buttonStyle(.pressable)
    }

    private func placeRow(_ place: LocationTarget, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "mappin.circle")
                .font(.title3)
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: place.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !place.subtitle.isEmpty {
                    Text(verbatim: place.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func useCoordinates() {
        switch CoordinateInputParser.parse(coordinateText) {
        case .coordinate(let latitude, let longitude):
            coordinateError = nil
            withAnimation(reduceMotion ? nil : MapAnimation.snappy) {
                target = LocationTarget(
                    name: String(format: "%.5f, %.5f", latitude, longitude),
                    subtitle: String(localized: "Entered using coordinates"),
                    latitude: latitude,
                    longitude: longitude
                )
            }
            coordinateText = ""
        case .invalid, .notCoordinates:
            coordinateError = String(localized: "Enter latitude and longitude, for example 25.0330, 121.5654.")
        }
    }

    // MARK: Result

    private var builtEntry: ScheduleEntry? {
        guard !weekdays.isEmpty else { return nil }
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let action: ScheduledAction
        switch kind {
        case .place:
            guard let target else { return nil }
            action = .place(target)
        case .walk, .drive:
            guard let target else { return nil }
            action = .route(mode: kind == .walk ? .walking : .driving, destination: target)
        case .drift:
            guard let areaID, let area = appModel.savedDriftAreas.first(where: { $0.id == areaID }) else { return nil }
            action = .drift(areaID: areaID, areaName: area.name)
        case .restore:
            action = .restore
        }
        return ScheduleEntry(
            id: entry?.id ?? UUID(),
            isEnabled: entry?.isEnabled ?? true,
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            weekdays: weekdays,
            action: action
        )
    }
}
