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
        // Weekdays, month-days and times of day are worked out here against `now`; the
        // system's detector reads them against the real clock (on a Friday, "fri 2pm" was
        // next Friday).
        switch dayAndTime(typed, now: now, calendar: calendar) {
        case .date(let own): return own > now ? own : nil
        case .invalid: return nil
        case .notOurs: break
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: typed, range: NSRange(typed.startIndex..., in: typed)),
              var found = match.date else { return nil }
        if typed.range(of: #"\d\s*(am|pm)\b|\d:\d|noon|midnight|morning|afternoon|evening|night"#, options: .regularExpression) == nil {
            found = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: found) ?? found
        }
        return found > now ? found : nil
    }

    static let weekdays = ["sun": 1, "sunday": 1, "mon": 2, "monday": 2, "tue": 3, "tues": 3, "tuesday": 3, "wed": 4, "wednesday": 4,
                           "thu": 5, "thur": 5, "thurs": 5, "thursday": 5, "fri": 6, "friday": 6, "sat": 7, "saturday": 7]
    static let months = ["jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4, "may": 5,
                         "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9,
                         "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12]

    /// "fri 2pm", "dec 3 9am", "12/3", "3pm", "today 5pm", "tomorrow noon": a day (or none)
    /// and a time (or none, meaning 7am). A weekday is its next one, today included while
    /// the time is ahead; a month-day already past is next year's; a time alone already
    /// past is tomorrow's. Nil when the text isn't one of these.
    /// What `dayAndTime` made of the text.
    enum Reading: Equatable {
        /// Not a day-and-time phrase; the system's detector may still read it.
        case notOurs
        /// Shaped like one but impossible ("feb 30", "13pm", "fri 2").
        case invalid
        case date(Date)

        init(_ date: Date?) { self = date.map(Reading.date) ?? .invalid }
    }

    static func dayAndTime(_ typed: String, now: Date, calendar: Calendar) -> Reading {
        let pattern = #"^(?:(?<month>[a-z]+) (?<dom>\d{1,2})(?:st|nd|rd|th)?(?![\d:]| ?[ap]m)|(?<day>(?!noon$|midnight$)[a-z]+)|(?<m>\d{1,2})/(?<d>\d{1,2}))?,? ?(?:at )?(?:(?<hour>\d{1,2})(?::(?<minute>\d{2}))? ?(?<ampm>am|pm)?|(?<word>noon|midnight))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: typed, range: NSRange(typed.startIndex..., in: typed)) else { return .notOurs }
        func group(_ name: String) -> String? {
            Range(match.range(withName: name), in: typed).map { String(typed[$0]) }
        }
        // The time of day.
        var hour = 7, minute = 0
        let hasTime = group("hour") != nil || group("word") != nil
        if let word = group("word") {
            hour = word == "noon" ? 12 : 0
        } else if let hourText = group("hour"), let typedHour = Int(hourText) {
            let ampm = group("ampm")
            // A bare number ("fri 2") is too vague; "14:00" is not.
            guard ampm != nil || group("minute") != nil else { return .invalid }
            minute = group("minute").flatMap(Int.init) ?? 0
            guard minute < 60 else { return .invalid }
            switch ampm {
            case "am": guard (1...12).contains(typedHour) else { return .invalid }; hour = typedHour % 12
            case "pm": guard (1...12).contains(typedHour) else { return .invalid }; hour = typedHour % 12 + 12
            default: guard typedHour < 24 else { return .invalid }; hour = typedHour
            }
        }
        let today = calendar.startOfDay(for: now)
        func at(_ day: Date) -> Date? { calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) }
        if let word = group("day") {
            switch word {
            case "today", "tonight":
                return Reading(at(today))
            case "tomorrow":
                return Reading(calendar.date(byAdding: .day, value: 1, to: today).flatMap(at))
            default:
                guard let weekday = weekdays[word] else { return .notOurs }
                let ahead = (weekday - calendar.component(.weekday, from: today) + 7) % 7
                guard let day = calendar.date(byAdding: .day, value: ahead, to: today), let time = at(day) else { return .invalid }
                return Reading(time > now ? time : calendar.date(byAdding: .day, value: 7, to: day).flatMap(at))
            }
        }
        let monthDay: (Int, Int)?
        if let name = group("month") {
            guard let month = months[name], let day = group("dom").flatMap(Int.init) else {
                // "fri 2", "tomorrow 3": a day with a bare number, too vague to guess.
                return weekdays[name] != nil || ["today", "tonight", "tomorrow"].contains(name) ? .invalid : .notOurs
            }
            monthDay = (month, day)
        } else if let m = group("m").flatMap(Int.init), let d = group("d").flatMap(Int.init) {
            monthDay = (m, d)
        } else {
            monthDay = nil
        }
        if let (month, day) = monthDay {
            let year = calendar.component(.year, from: now)
            for candidateYear in [year, year + 1] {
                let parts = DateComponents(year: candidateYear, month: month, day: day, hour: hour, minute: minute)
                // Feb 30 and the like are refused, not rolled into March.
                guard parts.isValidDate(in: calendar), let date = calendar.date(from: parts) else { return .invalid }
                if date > now { return .date(date) }
            }
            return .invalid
        }
        // A time alone.
        guard hasTime, let time = at(today) else { return .notOurs }
        return Reading(time > now ? time : calendar.date(byAdding: .day, value: 1, to: today).flatMap(at))
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
