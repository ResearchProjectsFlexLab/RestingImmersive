import Foundation

enum TimeFormatting {
    /// "9:05" style countdown text.
    static func countdown(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// "9 minutes, 5 seconds" style text for VoiceOver and summaries.
    static func spokenDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 60 ? [.minute, .second] : [.second]
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropAll
        let seconds = max(0, interval.rounded())
        if let text = formatter.string(from: seconds), !text.isEmpty {
            return text
        }
        return String(localized: "\(Int(seconds)) seconds")
    }
}
