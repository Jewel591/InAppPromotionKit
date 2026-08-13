import Foundation

enum PromotionCountdownFormatter {
    static func string(from remainingTime: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = remainingTime >= 60 * 60
            ? [.hour, .minute, .second]
            : [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: max(0, remainingTime)) ?? "00:00"
    }
}
