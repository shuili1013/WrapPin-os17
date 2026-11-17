import ActivityKit
import SwiftUI
import WidgetKit

@main
struct WrapPinLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        LocationActivityWidget()
    }
}

private typealias State = WrapPinActivityAttributes.ContentState
private typealias Route = WrapPinActivityAttributes.RouteProgress

struct LocationActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WrapPinActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "wrappin://live-activity"))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StatusIcon(state: state)
                        .font(.title2)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TrailingFigure(state: state)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(statusTitle(state))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accent(state))
                        Text(headline(state))
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let route = state.route {
                        RouteProgressRow(route: route, compact: false)
                            .padding(.horizontal, 4)
                    } else {
                        VStack(spacing: 4) {
                            if !state.subtitle.isEmpty {
                                Text(state.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Text(coordinateText(state))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                StatusIcon(state: state)
            } compactTrailing: {
                if let route = state.route {
                    Text(percentText(route))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(accent(state))
                } else {
                    ElapsedTime(state: state)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: 52)
                }
            } minimal: {
                if let route = state.route {
                    ProgressView(value: route.progress) {
                        StatusIcon(state: state).font(.caption2)
                    }
                    .progressViewStyle(.circular)
                    .tint(accent(state))
                } else {
                    StatusIcon(state: state)
                }
            }
            .widgetURL(URL(string: "wrappin://live-activity"))
            .keylineTint(accent(state))
        }
    }
}

private struct LockScreenView: View {
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accent(state).opacity(0.22))
                    StatusIcon(state: state)
                        .font(.title2.weight(.semibold))
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle(state))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent(state))
                    Text(headline(state))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if state.drift != nil {
                        Text(coordinateText(state))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    } else if state.route == nil {
                        Text(state.subtitle.isEmpty ? coordinateText(state) : state.subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    TrailingFigure(state: state)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                    Text(trailingCaption(state))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            if let route = state.route {
                RouteProgressRow(route: route, compact: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

/// The progress bar plus "x% · y left" under it.
private struct RouteProgressRow: View {
    let route: Route
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: route.progress)
                .progressViewStyle(.linear)
                .tint(routeAccent(route))
                .scaleEffect(x: 1, y: compact ? 1.6 : 1.3, anchor: .center)
            HStack {
                Text(percentText(route))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(compact ? .white : .primary)
                Spacer()
                RemainingText(route: route)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(compact ? Color.white.opacity(0.7) : .secondary)
            }
        }
    }
}

private struct RemainingText: View {
    let route: Route

    var body: some View {
        if route.hasArrived {
            Text("Arrived")
        } else if route.isPaused {
            Text("Paused")
        } else if let arrivesAt = route.arrivesAt, arrivesAt > Date() {
            HStack(spacing: 4) {
                Text(timerInterval: Date()...arrivesAt, countsDown: true)
                    .multilineTextAlignment(.trailing)
                Text("left")
            }
        } else {
            Text("Almost there")
        }
    }
}

private struct StatusIcon: View {
    let state: State

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(accent(state))
    }

    private var symbol: String {
        if state.status == .reconnecting { return "arrow.triangle.2.circlepath" }
        if let drift = state.drift {
            if drift.isPaused { return "pause.circle.fill" }
            switch drift.kind {
            case .wander: return "figure.walk.motion"
            case .jump: return "sparkles"
            case .jitter: return "dot.radiowaves.left.and.right"
            }
        }
        guard let route = state.route else { return "location.fill" }
        if route.hasArrived { return "flag.checkered" }
        if route.isPaused { return "pause.circle.fill" }
        return route.kind == .walking ? "figure.walk" : "car.fill"
    }
}

/// Elapsed time for a fixed location; the session timer for a route.
private struct TrailingFigure: View {
    let state: State

    var body: some View {
        ElapsedTime(state: state)
    }
}

private struct ElapsedTime: View {
    let state: State

    var body: some View {
        Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
            .multilineTextAlignment(.trailing)
    }
}

private func headline(_ state: State) -> String {
    state.drift?.areaName ?? state.route?.destinationName ?? state.placeName
}

private func statusTitle(_ state: State) -> LocalizedStringKey {
    if state.status == .reconnecting { return "Reconnecting…" }
    if let drift = state.drift {
        if drift.isPaused { return "Drift paused" }
        switch drift.kind {
        case .wander: return "Wandering in area"
        case .jump: return "Jumping in area"
        case .jitter: return "Drifting in place"
        }
    }
    guard let route = state.route else { return "Simulating location" }
    if route.hasArrived { return "Arrived" }
    if route.isPaused { return "Paused" }
    return route.kind == .walking ? "Walking to" : "Driving to"
}

private func trailingCaption(_ state: State) -> LocalizedStringKey {
    "Elapsed"
}

private func accent(_ state: State) -> Color {
    if state.status == .reconnecting { return .orange }
    if let drift = state.drift { return drift.isPaused ? .yellow : .purple }
    if let route = state.route { return routeAccent(route) }
    return .blue
}

private func routeAccent(_ route: Route) -> Color {
    if route.hasArrived { return .green }
    if route.isPaused { return .yellow }
    return route.kind == .walking ? .green : .blue
}

private func percentText(_ route: Route) -> String {
    "\(Int((route.progress * 100).rounded()))%"
}

private func coordinateText(_ state: State) -> String {
    String(format: "%.5f, %.5f", state.latitude, state.longitude)
}
