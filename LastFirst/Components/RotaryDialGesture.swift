//
//  RotaryDialGesture.swift
//  LastFirst
//
//  A rotary dial gesture tracker that converts circular finger motion
//  into continuous rotation values. Works like a physical scroll wheel:
//  clockwise rotation produces positive angular deltas, counter-clockwise
//  produces negative. Supports multi-revolution tracking without cancellation.
//

import SwiftUI

/// Tracks circular finger motion around a center point and converts it
/// to cumulative rotation in degrees. Designed for use with DragGesture.
///
/// The key insight: `atan2` gives us the absolute angle from center to touch.
/// By tracking the delta between consecutive angles (with wrap-around handling
/// at the ±180° boundary), we accumulate total rotation that correctly counts
/// full revolutions without cancellation.
struct RotaryDialTracker {

    /// The center point of the dial in the gesture view's local coordinate space.
    let center: CGPoint

    /// Total accumulated rotation in degrees since the drag started.
    /// Positive = clockwise, Negative = counter-clockwise.
    /// This value grows unbounded with multiple revolutions.
    private(set) var totalRotation: Double = 0

    /// The angle (degrees) of the previous touch sample.
    private var previousAngle: Double = 0

    /// Whether we've received the first touch sample yet.
    private var hasStarted: Bool = false

    init(center: CGPoint) {
        self.center = center
    }

    /// Begin or continue tracking with a new touch point.
    /// Returns the incremental rotation (degrees) for this sample.
    /// Positive = clockwise, Negative = counter-clockwise.
    @discardableResult
    mutating func track(point: CGPoint) -> Double {
        let currentAngle = Self.angle(from: center, to: point)

        guard hasStarted else {
            // First sample: just record the starting angle, no delta yet.
            previousAngle = currentAngle
            hasStarted = true
            return 0
        }

        // Compute the shortest angular difference between previous and current.
        // This correctly handles the wrap-around at ±180°.
        let delta = Self.normalizedDelta(from: previousAngle, to: currentAngle)
        previousAngle = currentAngle
        totalRotation += delta

        return delta
    }

    /// Reset the tracker for a new drag session.
    mutating func reset() {
        totalRotation = 0
        previousAngle = 0
        hasStarted = false
    }

    // MARK: - Angle Math

    /// Computes the angle in degrees from `center` to `point`.
    /// 0° = 12 o'clock (top), 90° = 3 o'clock (right),
    /// ±180° = 6 o'clock (bottom), -90° = 9 o'clock (left).
    ///
    /// Uses atan2(x, -y) so that:
    /// - Moving right from top   → positive angle (clockwise)
    /// - Moving left from top    → negative angle (counter-clockwise)
    static func angle(from center: CGPoint, to point: CGPoint) -> Double {
        let dx = point.x - center.x
        let dy = point.y - center.y
        // atan2(x, -y) gives 0 at top, increasing clockwise
        let radians = atan2(dx, -dy)
        return radians * 180.0 / .pi
    }

    /// Returns the shortest signed angular difference from `a` to `b`.
    /// Result is in the range (-180, 180].
    /// Positive means `b` is clockwise from `a`.
    static func normalizedDelta(from a: Double, to b: Double) -> Double {
        var delta = b - a
        // Wrap into (-180, 180] range
        while delta > 180 { delta -= 360 }
        while delta <= -180 { delta += 360 }
        return delta
    }
}
