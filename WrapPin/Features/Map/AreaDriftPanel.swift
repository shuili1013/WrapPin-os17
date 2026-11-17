import MapKit
import Observation
import SwiftUI

/// Bottom card for area drift: shows the box, the drift style and its
/// controls, and saves or loads boxes.
struct AreaDriftPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.mapPanelMaximumHeight) private var maximumHeight
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
    let onClose: () -> Void
    @Binding var isCollapsed: Bool

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
        VStack(spacing: 0) {
            MapPanelDisclosure(isCollapsed: $isCollapsed)
                .padding(.horizontal, 16)
            scrollableContent
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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

    /// The disclosure header stays put; the rest scrolls when it does not fit.
    @ViewBuilder
    private var scrollableContent: some View {
        let content = details
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        if let maximumHeight {
            MapPanelViewport(maximumHeight: max(120, maximumHeight - 44)) {
                content
            }
        } else {
            content
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !isCollapsed {
                Group {
                    if isEditing {
                        Label("Drag the corners to resize, the centre to move, and the top handle to rotate.", systemImage: "hand.draw")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    modePicker
                    modeControls
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if case .failed(let message) = phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            actions

            if !isCollapsed {
                storageRow
                    .transition(.opacity)
            }
        }
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
            if isRunning && isCollapsed {
                // Collapsed: both essential actions on one row.
                HStack(spacing: 10) {
                    pauseButton
                    restoreButton
                }
            } else if isRunning {
                pauseButton

                HStack(spacing: 10) {
                    Button(action: onStopDrifting) {
                        actionLabel(String(localized: "Stay Here"), symbol: "mappin")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(phase == .preparing || phase == .stopping)

                    restoreButton
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

    private var pauseButton: some View {
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
    }

    private var restoreButton: some View {
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

    private var storageRow: some View {
        HStack(spacing: 10) {
            Button {
                draftName = area.name
                isNaming = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .contentTransition(.symbolEffect(.replace))
                    if isSaved {
                        Text("Saved")
                    } else {
                        Text("Save Area")
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            }

            Button(action: onShowSaved) {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack")
                    Text("Saved Areas")
                    if savedAreaCount > 0 {
                        Text(verbatim: "\(savedAreaCount)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.purple.opacity(0.25), in: Capsule())
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
            }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .tint(.purple)
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
        let size = "\(format(area.widthMetres)) × \(format(area.heightMetres))"
        let angle = Int(area.rotationDegrees.rounded()) % 360
        return angle == 0 ? size : "\(size) · \(angle)°"
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

/// Corner, centre and rotation handles drawn over the map while editing the
/// box. The box itself is a MapPolygon in the map content, so it stays glued
/// to the map; these handles are recomputed from the map proxy on every
/// camera change.
struct DriftBoxEditor: View {
    @Binding var area: DriftArea?
    let proxy: MapProxy
    /// Bumped on camera changes so the handles follow pans and zooms.
    let camera: DriftEditorCamera

    private static let space = "driftBoxEditor"
    /// Screen distance from the top edge to the rotation handle.
    private static let rotationStalk: CGFloat = 44
    private static let snapDegrees: Double = 4

    @State private var moveStart: (center: CGPoint, area: DriftArea)?
    @State private var resizeAnchor: CLLocationCoordinate2D?
    @State private var lastSnappedAngle: Double?

    var body: some View {
        GeometryReader { _ in
            // Reading the revision makes pans and zooms move the handles.
            let _ = camera.revision
            if let area, let points = screenCorners(of: area) {
                let center = midpoint(points)
                let topMiddle = midpoint([points[0], points[1]])
                let rotationPoint = rotationHandlePoint(center: center, topMiddle: topMiddle)
                ZStack {
                    Path { path in
                        path.move(to: topMiddle)
                        path.addLine(to: rotationPoint)
                    }
                    .stroke(.purple, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .allowsHitTesting(false)

                    ForEach(0..<4, id: \.self) { index in
                        handle(size: 22, symbol: nil)
                            .position(points[index])
                            .gesture(resizeGesture(corner: index, area: area))
                    }
                    handle(size: 40, symbol: "arrow.up.and.down.and.arrow.left.and.right")
                        .position(center)
                        .gesture(moveGesture(center: center, area: area))
                    handle(size: 32, symbol: "arrow.clockwise")
                        .position(rotationPoint)
                        .gesture(rotateGesture(area: area))
                }
            }
        }
        .coordinateSpace(name: Self.space)
    }

    private func handle(size: CGFloat, symbol: String?) -> some View {
        ZStack {
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            Circle()
                .strokeBorder(.purple, lineWidth: 3)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.purple)
            }
        }
        .frame(width: size, height: size)
        // Generous touch target around the small visual handle.
        .frame(width: 52, height: 52)
        .contentShape(Circle())
    }

    private func midpoint(_ points: [CGPoint]) -> CGPoint {
        CGPoint(
            x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
            y: points.map(\.y).reduce(0, +) / CGFloat(points.count)
        )
    }

    private func rotationHandlePoint(center: CGPoint, topMiddle: CGPoint) -> CGPoint {
        let dx = topMiddle.x - center.x
        let dy = topMiddle.y - center.y
        let length = max((dx * dx + dy * dy).squareRoot(), 0.001)
        return CGPoint(
            x: topMiddle.x + dx / length * Self.rotationStalk,
            y: topMiddle.y + dy / length * Self.rotationStalk
        )
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
                // Measured along the box's own axes, so a rotated box keeps its angle.
                self.area = DriftArea(
                    id: area.id,
                    name: area.name,
                    corner: (anchor.latitude, anchor.longitude),
                    corner: (dragged.latitude, dragged.longitude),
                    rotationDegrees: area.rotationDegrees,
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
                var moved = self.area ?? start.area
                moved.centerLatitude = coordinate.latitude
                moved.centerLongitude = coordinate.longitude
                self.area = moved
            }
            .onEnded { _ in moveStart = nil }
    }

    /// Turns the box so its top edge faces the finger; snaps to 0°/90°/180°/270°.
    private func rotateGesture(area: DriftArea) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard
                    let current = self.area,
                    let finger = proxy.convert(value.location, from: .local)
                else { return }
                var angle = current.bearingDegrees(to: finger.latitude, longitude: finger.longitude)
                let nearestRight = (angle / 90).rounded() * 90
                if abs(angle - nearestRight) <= Self.snapDegrees {
                    angle = DriftArea.normalisedDegrees(nearestRight)
                    if lastSnappedAngle != angle {
                        lastSnappedAngle = angle
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } else {
                    lastSnappedAngle = nil
                }
                var rotated = current
                rotated.rotationDegrees = DriftArea.normalisedDegrees(angle)
                self.area = rotated
            }
            .onEnded { _ in lastSnappedAngle = nil }
    }
}
