import ActivityKit
import SwiftUI
import WidgetKit

@main
struct WrapPinLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        LocationActivityWidget()
    }
}

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
                    StatusIcon(status: state.status)
                        .font(.title2)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedTime(state: state)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(statusTitle(state.status))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(statusColor(state.status))
                        Text(state.placeName)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
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
            } compactLeading: {
                StatusIcon(status: state.status)
            } compactTrailing: {
                ElapsedTime(state: state)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(maxWidth: 52)
            } minimal: {
                StatusIcon(status: state.status)
            }
            .widgetURL(URL(string: "wrappin://live-activity"))
            .keylineTint(statusColor(state.status))
        }
    }
}

private struct LockScreenView: View {
    let state: WrapPinActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusColor(state.status).opacity(0.22))
                StatusIcon(status: state.status)
                    .font(.title2.weight(.semibold))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle(state.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(state.status))
                Text(state.placeName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(state.subtitle.isEmpty ? coordinateText(state) : state.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                ElapsedTime(state: state)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                Text("Elapsed")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct StatusIcon: View {
    let status: WrapPinActivityAttributes.Status

    var body: some View {
        Image(systemName: status == .active ? "location.fill" : "arrow.triangle.2.circlepath")
            .foregroundStyle(statusColor(status))
    }
}

private struct ElapsedTime: View {
    let state: WrapPinActivityAttributes.ContentState

    var body: some View {
        Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
            .multilineTextAlignment(.trailing)
    }
}

private func statusTitle(_ status: WrapPinActivityAttributes.Status) -> LocalizedStringKey {
    switch status {
    case .active: "Simulating location"
    case .reconnecting: "Reconnecting…"
    }
}

private func statusColor(_ status: WrapPinActivityAttributes.Status) -> Color {
    switch status {
    case .active: .blue
    case .reconnecting: .orange
    }
}

private func coordinateText(_ state: WrapPinActivityAttributes.ContentState) -> String {
    String(format: "%.5f, %.5f", state.latitude, state.longitude)
}
