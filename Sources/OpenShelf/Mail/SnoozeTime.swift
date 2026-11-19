import Foundation

/// When a snoozed message comes back: David's presets (ROADMAP I4) and typed times.
/// Pure: every answer is worked out from a given "now" and calendar.
enum SnoozeTime {
    struct Preset: Equatable, Sendable {
        var name: String
        /// Words that also choose it, beyond its name.
        var aliases: [String]
    }

    /// David, 2026-11-19: tomorrow morning 7am, this afternoon 2pm, tonight 5pm, in two days
    /// 7am, this weekend Saturday 7am, next week Monday 7am.
    static let presets: [Preset] = [
        Preset(name: "tomorrow morning", aliases: ["tomorrow"]),
        Preset(name: "this afternoon", aliases: ["afternoon"]),
        Preset(name: "tonight", aliases: []),
        Preset(name: "in two days", aliases: ["in 2 days"]),
        Preset(name: "this weekend", aliases: ["weekend"]),
        Preset(name: "next week", aliases: []),
    ]

    /// A preset's time. A time of day already past today ("this afternoon" at 4pm) is the
    /// next day's.
    static func date(of preset: Preset, now: Date, calendar: Calendar) -> Date {
        switch preset.name {
        case "tomorrow morning": return at(7, daysAfter: 1, now: now, calendar: calendar)
        case "this afternoon": return nextOccurrence(hour: 14, now: now, calendar: calendar)
        case "tonight": return nextOccurrence(hour: 17, now: now, calendar: calendar)
        case "in two days": return at(7, daysAfter: 2, now: now, calendar: calendar)
        case "this weekend": return next(weekday: 7, hour: 7, now: now, calendar: calendar)
        default: return next(weekday: 2, hour: 7, now: now, calendar: calendar)
        }
    }

    /// What `text` means: a preset by name, "in N minutes/hours/days/weeks", or a date the
    /// system's detector reads ("fri 2pm", "dec 3 9am"). A date with no time of day is 7am.
    /// Nil when nothing is understood or the time has passed.
    static func parse(_ text: String, now: Date, calendar: Calendar) -> Date? {
        let typed = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return nil }
        if let preset = presets.first(where: { $0.name == typed || $0.aliases.contains(typed) }) {
            return date(of: preset, now: now, calendar: calendar)
        }
        // "in N units" is ours alone, even when N makes no sense ("in 5000 days").
        if typed.range(of: Self.relativePattern, options: .regularExpression) != nil {
            return relative(typed, now: now, calendar: calendar)
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: typed, range: NSRange(typed.startIndex..., in: typed)),
              var found = match.date else { return nil }
        if typed.range(of: #"\d\s*(am|pm)\b|\d:\d|noon|midnight|morning|afternoon|evening|night"#, options: .regularExpression) == nil {
            found = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: found) ?? found
        }
        return found > now ? found : nil
    }

    static let relativePattern = #"^in (\d+|[a-z]+) (minutes?|mins?|hours?|hrs?|days?|weeks?)$"#

    /// "in 3 hours", "in an hour", "in two days": minutes and hours from now; days and weeks
    /// at 7am, as the presets are.
    static func relative(_ typed: String, now: Date, calendar: Calendar) -> Date? {
        let words = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10]
        guard let regex = try? NSRegularExpression(pattern: relativePattern),
              let match = regex.firstMatch(in: typed, range: NSRange(typed.startIndex..., in: typed)),
              let amountRange = Range(match.range(at: 1), in: typed), let unitRange = Range(match.range(at: 2), in: typed) else { return nil }
        let amountText = String(typed[amountRange])
        guard let amount = Int(amountText) ?? words[amountText], amount > 0, amount <= 1000 else { return nil }
        let unit = typed[unitRange]
        if unit.hasPrefix("min") { return calendar.date(byAdding: .minute, value: amount, to: now) }
        if unit.hasPrefix("h") { return calendar.date(byAdding: .hour, value: amount, to: now) }
        let days = unit.hasPrefix("w") ? amount * 7 : amount
        return at(7, daysAfter: days, now: now, calendar: calendar)
    }

    /// How the prompt shows a time: "Fri, Nov 21 at 2:00 PM".
    static func describe(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        return formatter.string(from: date)
    }

    private static func at(_ hour: Int, daysAfter days: Int, now: Date, calendar: Calendar) -> Date {
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    private static func nextOccurrence(hour: Int, now: Date, calendar: Calendar) -> Date {
        let today = at(hour, daysAfter: 0, now: now, calendar: calendar)
        return today > now ? today : at(hour, daysAfter: 1, now: now, calendar: calendar)
    }

    /// The first `weekday` (1 Sunday … 7 Saturday) at `hour` after now.
    private static func next(weekday: Int, hour: Int, now: Date, calendar: Calendar) -> Date {
        calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: 0, second: 0, weekday: weekday), matchingPolicy: .nextTime)!
    }
}
