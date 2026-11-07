import Foundation
import CoreGraphics

/// One automatic photo per stable card. Re-arm only after the card leaves the
/// frame; tiny camera motion must never create dozens of duplicate captures.
public struct CaptureGate: Sendable {
    public private(set) var isArmed = true
    private var last: CGRect?
    private var lastTime: TimeInterval?
    private var stableSince: TimeInterval?
    private var absentSince: TimeInterval?
    public init() {}
    public mutating func didCapture() { isArmed = false; stableSince = nil }
    public mutating func update(rect: CGRect?, at time: TimeInterval, focusReady: Bool = true, qualityReady: Bool = true) -> Bool {
        guard let rect else {
            last = nil; stableSince = nil
            // Losing the rectangle during autofocus is not proof of removal.
            guard focusReady else { absentSince = nil; return false }
            if absentSince == nil { absentSince = time }
            if time - absentSince! >= 0.55 { isArmed = true }
            return false
        }
        absentSince = nil
        guard qualityReady else { last = nil; stableSince = nil; return false }
        guard isArmed else { return false }
        // Compare consecutive frames instead of requiring the hand to return to
        // one fixed position. Gentle drift is fine; rapid sweeps are not.
        let size = min(rect.width, rect.height)
        let tolerance = max(0.035, min(0.08, size * 0.16))
        let maximumSpeed = min(0.45, size * 0.9)
        let elapsed = lastTime.map { time - $0 } ?? 0
        defer { last = rect; lastTime = time }
        if let last, abs(last.midX - rect.midX) <= tolerance, abs(last.midY - rect.midY) <= tolerance,
           abs(last.width - rect.width) <= tolerance, abs(last.height - rect.height) <= tolerance,
           elapsed > 0, elapsed <= 1,
           hypot(last.midX - rect.midX, last.midY - rect.midY) / elapsed <= maximumSpeed {
            // Keep tracking acceptable movement while autofocus adjusts. Once
            // it finishes, do not demand another full stability window.
            if focusReady, let since = stableSince, time - since >= 0.12 { didCapture(); return true }
        } else { stableSince = time }
        return false
    }
}
