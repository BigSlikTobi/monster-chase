import Foundation

/// Live capture guidance, not a claim that a card or finish is identifiable.
public enum CaptureReadiness: Equatable, Sendable {
    case missingCard, tooSmall, focusing, ready

    public static func evaluate(frame: ScanCardFrame?, focusReady: Bool) -> Self {
        guard let frame else { return .missingCard }
        guard frame.bounds.width * frame.bounds.height >= 0.18 else { return .tooSmall }
        guard focusReady else { return .focusing }
        // Preview OCR can miss small names on an otherwise usable photo.
        // Read text from the captured image; it must not gate the shutter.
        return .ready
    }

    public var guidance: String {
        switch self {
        case .missingCard: "Alle vier Ecken ins Bild halten"
        case .tooSmall: "Karte näher an die Kamera halten"
        case .focusing: "Kamera fokussiert"
        case .ready: "Karte erkannt · Aufnahme bereit"
        }
    }
}
