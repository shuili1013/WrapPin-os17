import MapKit
import SwiftUI
import UIKit

/// Adds a UIKit long-press recognizer directly to the MKMapView that backs the
/// SwiftUI `Map`. A SwiftUI long-press + drag gesture attached to the map
/// competes with MapKit's own pinch and pan recognizers, which made zooming
/// stutter and the long press itself unreliable. A UIKit recognizer installed
/// on the map view recognizes alongside MapKit's gestures instead.
struct MapLongPressInstaller: UIViewRepresentable {
    var minimumDuration: TimeInterval = 0.4
    var onLongPress: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLongPress: onLongPress, minimumDuration: minimumDuration)
    }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.onLongPress = onLongPress
        uiView.coordinator = context.coordinator
        uiView.installIfNeeded()
    }

    /// An invisible view whose only job is to find the map once it is in a window.
    final class ProbeView: UIView {
        weak var coordinator: Coordinator?
        private var retryCount = 0

        override func didMoveToWindow() {
            super.didMoveToWindow()
            retryCount = 0
            installIfNeeded()
        }

        func installIfNeeded() {
            guard let coordinator, let window else { return }
            if let mapView = coordinator.mapView, mapView.window != nil { return }
            if let mapView = Self.findMapView(in: window) {
                coordinator.attach(to: mapView)
            } else if retryCount < 20 {
                // The map view can appear a moment after this probe.
                retryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.installIfNeeded()
                }
            }
        }

        private static func findMapView(in view: UIView) -> MKMapView? {
            if let mapView = view as? MKMapView { return mapView }
            for subview in view.subviews {
                if let found = findMapView(in: subview) { return found }
            }
            return nil
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onLongPress: (CLLocationCoordinate2D) -> Void
        weak var mapView: MKMapView?
        private let recognizer: UILongPressGestureRecognizer
        private let feedback = UIImpactFeedbackGenerator(style: .medium)

        init(onLongPress: @escaping (CLLocationCoordinate2D) -> Void, minimumDuration: TimeInterval) {
            self.onLongPress = onLongPress
            recognizer = UILongPressGestureRecognizer()
            super.init()
            recognizer.minimumPressDuration = minimumDuration
            recognizer.allowableMovement = 14
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delegate = self
            recognizer.addTarget(self, action: #selector(handle(_:)))
        }

        func attach(to mapView: MKMapView) {
            guard self.mapView !== mapView else { return }
            recognizer.view?.removeGestureRecognizer(recognizer)
            mapView.addGestureRecognizer(recognizer)
            self.mapView = mapView
            feedback.prepare()
        }

        @objc private func handle(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let mapView else { return }
            // Ignore a press that began with two fingers (the start of a pinch).
            guard recognizer.numberOfTouches == 1 else { return }
            let point = recognizer.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            guard CLLocationCoordinate2DIsValid(coordinate) else { return }
            feedback.impactOccurred()
            feedback.prepare()
            onLongPress(coordinate)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
