import Foundation

/// Canonical hex color codec: parses `#RRGGBB` / `#RRGGBBAA` and always
/// formats `#RRGGBBAA` — alpha last in both directions (C8; the original
/// parsed `#AARRGGBB` but wrote `#RRGGBBAA`, swapping alpha and red on every
/// round trip).
public struct HexColor: Equatable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 0xFF) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static func parse(_ string: String) -> HexColor? {
        var digits = string.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6 || digits.count == 8,
              digits.allSatisfy(\.isHexDigit),
              let value = UInt64(digits, radix: 16)
        else { return nil }
        let hasAlpha = digits.count == 8
        let rgb = hasAlpha ? value >> 8 : value
        return HexColor(
            red: UInt8((rgb >> 16) & 0xFF),
            green: UInt8((rgb >> 8) & 0xFF),
            blue: UInt8(rgb & 0xFF),
            alpha: hasAlpha ? UInt8(value & 0xFF) : 0xFF
        )
    }

    public var formatted: String {
        String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }
}
