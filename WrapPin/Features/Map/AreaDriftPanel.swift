import MapKit
import Observation
import SwiftUI

/// Bottom card for area drift: shows the box, the drift style and its
/// controls, and saves or loads boxes.
struct AreaDriftPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let area: DriftArea
    let settings: DriftSettings
    let phase: AreaDriftPhase
    let isPaired: Bool
    let isSaved: Bool
    let savedAreaCount: Int
    let isPausedAtWaypoint: Bool
    let onSettingsChange: (DriftSettings) -> Void
    let onStart: () -> Void
    let onTogglePause: () -> Void
    let onStopDrifting: () -> Void
    let onStopAndRestore: () -> Void
    let onSave: (String) -> Void
    let onShowSaved: () -> Void
    let onFitToView: () -> Void
    let onClose: () -> Void

    @State private var isNaming = false
    @State private var draftName = ""
    @State private var isConfirmingRestore = false

    private var isRunning: Bool {
        switch phase {
        case .preparing, .running, .paused, .stopping: true
        case .idle, .failed: false
        }
    }

    private var isEditing: Bool { !isRunning }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isEditing {
                Label("Drag the corners to resize the box, or the centre handle to move it.", systemImage: "hand.draw")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            modePicker
            modeControls

            if case .failed(let message) = phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            actions
            storageRow
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .animation(reduceMotion ? nil : MapAnimation.snappy, value: phase)
        .animation(reduceMotion ? nil : MapAnimation.snappy, value: settings.mode)
        .alert("Save Area", isPresented: $isNaming) {
            TextField("Name", text: $draftName)
            Button("Save") {
                let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave(name.isEmpty ? area.name : name)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved areas can be reused from the list next time.")
        }
        .confirmationDialog(
            "Stop and restore the real location?",
            isPresented: $isConfirmingRestore,
            titleVisibility: .visible
        ) {
            Button("Stop & Restore", role: .destructive, action: onStopAndRestore)
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("map.areaDriftPanel")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.purple)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
                    .contentTransition(.opacity)
                Text(verbatim: area.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(verbatim: sizeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isEditing {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Close Area Drift")
            }
        }
    }

    private var modePicker: some View {
        Picker("Drift style", selection: Binding(
            get: { settings.mode },
            set: { mode in
                var updated = settings
                updated.mode = mode
                onSettingsChange(updated)
            }
        )) {
            Text("Wander").tag(DriftMode.wander)
            Text("Jump").tag(DriftMode.jump)
            Text("Wobble").tag(DriftMode.jitter)
        }
        .pickerStyle(.segmented)
        .disabled(phase == .stopping)
    }

    @ViewBuilder
    private var modeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch settings.mode {
            case .wander:
                Text("Walks to random points inside the box and sometimes stops for a while.")
                    .modeDescription()
                sliderRow(
                    title: String(localized: "Speed"),
                    value: settings.wanderSpeedKilometresPerHour,
                    range: DriftSettings.wanderSpeedRange,
                    step: 0.5,
                    label: String(format: "%.1f km/h", settings.wanderSpeedKilometresPerHour)
                ) { value in
                    var updated = settings
                    updated.wanderSpeedKilometresPerHour = value
                    onSettingsChange(updated)
                }
                sliderRow(
                    title: String(localized: "Longest stop"),
                    value: settings.maximumPauseSeconds,
                    range: DriftSettings.maximumPauseRange,
                    step: 5,
                    label: settings.maximumPauseSeconds == 0
                        ? String(localized: "No stops")
                        : String(format: NSLocalizedString("%d s", comment: ""), Int(settings.maximumPauseSeconds))
                ) { value in
                    var updated = settings
                    updated.maximumPauseSeconds = value
                    onSettingsChange(updated)
                }
            case .jump:
                Text("Jumps straight to a random point inside the box at a fixed interval.")
                    .modeDescription()
                sliderRow(
                    title: String(localized: "Every"),
                    value: settings.jumpIntervalSeconds,
                    range: DriftSettings.jumpIntervalRange,
                    step: 1,
                    label: String(format: NSLocalizedString("%d s", comment: ""), Int(settings.jumpIntervalSeconds))
                ) { value in
                    var updated = settings
                    updated.jumpIntervalSeconds = value
                    onSettingsChange(updated)
                }
            case .jitter:
                Text("Wobbles gently around the centre of the box, like GPS noise.")
                    .modeDescription()
                sliderRow(
                    title: String(localized: "Radius"),
                    value: settings.jitterRadiusMetres,
                    range: DriftSettings.jitterRadiusRange,
                    step: 1,
                    label: String(format: "%d m", Int(settings.jitterRadiusMetres))
                ) { value in
                    var updated = settings
                    updated.jitterRadiusMetres = value
                    onSettingsChange(updated)
                }
            }
        }
        .transition(.opacity)
    }

    private func sliderRow(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        label: String,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(verbatim: label)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Slider(
                value: Binding(get: { value }, set: { onChange(($0 / step).rounded() * step) }),
                in: range
            )
            .tint(.purple)
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if isRunning {
                Button(action: onTogglePause) {
                    actionLabel(
                        phase == .paused ? String(localized: "Resume") : String(localized: "Pause"),
                        symbol: phase == .paused ? "play.fill" : "pause.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.purple)
                .disabled(phase == .preparing || phase == .stopping)

                HStack(spacing: 10) {
                    Button(action: onStopDrifting) {
                        actionLabel(String(localized: "Stay Here"), symbol: "mappin")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(phase == .preparing || phase == .stopping)

                    Button(role: .destructive) {
                        isConfirmingRestore = true
                    } label: {
                        actionLabel(String(localized: "Stop & Restore"), symbol: "stop.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.red)
                    .disabled(phase == .stopping)
                }
            } else {
                Button(action: onStart) {
                    actionLabel(String(localized: "Start Drifting"), symbol: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.purple)
                .disabled(!isPaired)

                if !isPaired {
                    Text("Pair this iPhone in Device Setup first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var storageRow: some View {
        HStack(spacing: 10) {
            Button {
                draftName = area.name
                isNaming = true
            } label: {
                Group {
                    if isSaved {
                        Label("Saved", systemImage: "bookmark.fill")
                    } else {
                        Label("Save Area", systemImage: "bookmark")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)

            Button(action: onShowSaved) {
                Label {
                    if savedAreaCount > 0 {
                        Text(String(format: NSLocalizedString("Saved Areas (%d)", comment: ""), savedAreaCount))
                    } else {
                        Text("Saved Areas")
                    }
                } icon: {
                    Image(systemName: "list.bullet")
                }
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)

            if isEditing {
                Button(action: onFitToView) {
                    Image(systemName: "viewfinder")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Fit the box to the visible map")
            }
        }
        .font(.subheadline.weight(.medium))
    }

    private func actionLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .contentTransition(.symbolEffect(.replace))
            Text(verbatim: title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 22)
    }

    private var statusSymbol: String {
        switch phase {
        case .preparing, .stopping: "hourglass"
        case .paused: "pause.circle.fill"
        case .running:
            isPausedAtWaypoint ? "figure.stand" : modeSymbol
        case .idle, .failed: "square.dashed"
        }
    }

    private var modeSymbol: String {
        switch settings.mode {
        case .wander: "figure.walk.motion"
        case .jump: "sparkles"
        case .jitter: "dot.radiowaves.left.and.right"
        }
    }

    private var statusTitle: String {
        switch phase {
        case .preparing: String(localized: "Connecting…")
        case .running:
            switch settings.mode {
            case .wander:
                isPausedAtWaypoint ? String(localized: "Stopped for a moment") : String(localized: "Wandering in the box")
            case .jump: String(localized: "Jumping around the box")
            case .jitter: String(localized: "Wobbling in place")
            }
        case .paused: String(localized: "Drift paused")
        case .stopping: String(localized: "Stopping…")
        case .idle, .failed: String(localized: "Area Drift")
        }
    }

    private var sizeText: String {
        func format(_ metres: Double) -> String {
            metres >= 1_000 ? String(format: "%.2f km", metres / 1_000) : String(format: "%.0f m", metres)
        }
        return "\(format(area.widthMetres)) × \(format(area.heightMetres))"
    }
}

private extension Text {
    func modeDescription() -> some View {
        self
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
@Observable
final class DriftEditorCamera {
    var revision = 0
}

/// Corner and centre handles drawn over the map while editing the box. The
/// box itself is a MapPolygon in the map content, so it stays glued to the
/// map; these handles are recomputed from the map proxy on every camera change.
struct DriftBoxEditor: View {
    @Binding var area: DriftArea?
    let proxy: MapProxy
    /// Bumped on camera changes so the handles follow pans and zooms.
    let camera: DriftEditorCamera

    private static let space = "driftBoxEditor"
    @State private var moveStart: (center: CGPoint, area: DriftArea)?
    @State private var resizeAnchor: CLLocationCoordinate2D?

    var body: some View {
        GeometryReader { _ in
            // Reading the revision makes pans and zooms move the handles.
            let _ = camera.revision
            if let area, let points = screenCorners(of: area) {
                let center = CGPoint(
                    x: points.map(\.x).reduce(0, +) / 4,
                    y: points.map(\.y).reduce(0, +) / 4
                )
                ZStack {
                    ForEach(0..<4, id: \.self) { index in
                        handle(symbol: nil)
                            .position(points[index])
                            .gesture(resizeGesture(corner: index, area: area))
                    }
                    handle(symbol: "arrow.up.and.down.and.arrow.left.and.right")
                        .position(center)
                        .gesture(moveGesture(center: center, area: area))
                }
            }
        }
        .coordinateSpace(name: Self.space)
    }

    private func handle(symbol: String?) -> some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: symbol == nil ? 22 : 40, height: symbol == nil ? 22 : 40)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            Circle()
                .strokeBorder(.purple, lineWidth: 3)
                .frame(width: symbol == nil ? 22 : 40, height: symbol == nil ? 22 : 40)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.purple)
            }
        }
        // Generous touch target around the small visual handle.
        .frame(width: 52, height: 52)
        .contentShape(Circle())
    }

    private func screenCorners(of area: DriftArea) -> [CGPoint]? {
        let points = area.corners.compactMap { corner in
            proxy.convert(
                CLLocationCoordinate2D(latitude: corner.latitude, longitude: corner.longitude),
                to: .local
            )
        }
        return points.count == 4 ? points : nil
    }

    private func resizeGesture(corner index: Int, area: DriftArea) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if resizeAnchor == nil {
                    let opposite = area.corners[(index + 2) % 4]
                    resizeAnchor = CLLocationCoordinate2D(latitude: opposite.latitude, longitude: opposite.longitude)
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                guard
                    let anchor = resizeAnchor,
                    let dragged = proxy.convert(value.location, from: .local)
                else { return }
                self.area = DriftArea(
                    id: area.id,
                    name: area.name,
                    corner: (anchor.latitude, anchor.longitude),
                    corner: (dragged.latitude, dragged.longitude),
                    createdAt: area.createdAt
                )
            }
            .onEnded { _ in resizeAnchor = nil }
    }

    private func moveGesture(center: CGPoint, area: DriftArea) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if moveStart == nil {
                    moveStart = (center, area)
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                guard let start = moveStart else { return }
                let point = CGPoint(
                    x: start.center.x + value.translation.width,
                    y: start.center.y + value.translation.height
                )
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                var moved = start.area
                moved.centerLatitude = coordinate.latitude
                moved.centerLongitude = coordinate.longitude
                self.area = moved
            }
            .onEnded { _ in moveStart = nil }
    }
}
