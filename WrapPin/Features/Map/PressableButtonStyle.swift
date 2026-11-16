import SwiftUI

/// The plain button look with a quick shrink-and-dim while pressed, so icon
/// buttons and text links respond visibly to touch. Respects Reduce Motion.
struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, pressedScale: pressedScale)
    }

    private struct PressableBody: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ButtonStyleConfiguration
        let pressedScale: CGFloat

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
                .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.65),
                    value: configuration.isPressed
                )
        }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// Shared animation curves for the map screen.
enum MapAnimation {
    static let panel = Animation.spring(response: 0.38, dampingFraction: 0.86)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.8)
}
