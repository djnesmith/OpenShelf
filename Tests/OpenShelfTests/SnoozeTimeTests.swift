import Foundation
import Testing
@testable import OpenShelf

/// The snooze prompt's times, worked out from a fixed "now" (ROADMAP I4).
struct SnoozeTimeTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    /// Wednesday 2026-11-18 at the given time, New York.
    static func wednesday(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: hour, minute: minute))!
    }

    static func describe(_ date: Date?) -> String? {
        date.map { SnoozeTime.describe($0, calendar: calendar) }
    }

    @Test(arguments: [
        ("tomorrow morning", 10, "Thu, Nov 19 at 7:00 AM"),
        ("this afternoon", 10, "Wed, Nov 18 at 2:00 PM"),
        // Past today: the next day at that time.
        ("this afternoon", 16, "Thu, Nov 19 at 2:00 PM"),
        ("tonight", 10, "Wed, Nov 18 at 5:00 PM"),
        ("tonight", 18, "Thu, Nov 19 at 5:00 PM"),
        ("in two days", 10, "Fri, Nov 20 at 7:00 AM"),
        ("this weekend", 10, "Sat, Nov 21 at 7:00 AM"),
        ("next week", 10, "Mon, Nov 23 at 7:00 AM"),
    ])
    func presets(name: String, hour: Int, expected: String) {
        let preset = SnoozeTime.presets.first { $0.name == name }!
        #expect(Self.describe(SnoozeTime.date(of: preset, now: Self.wednesday(hour), calendar: Self.calendar)) == expected)
    }

    @Test(arguments: [
        ("Tomorrow", "Thu, Nov 19 at 7:00 AM"),
        ("weekend", "Sat, Nov 21 at 7:00 AM"),
        ("in 2 days", "Fri, Nov 20 at 7:00 AM"),
        ("in 3 hours", "Wed, Nov 18 at 1:00 PM"),
        ("in an hour", "Wed, Nov 18 at 11:00 AM"),
        ("in 45 minutes", "Wed, Nov 18 at 10:45 AM"),
        ("in two weeks", "Wed, Dec 2 at 7:00 AM"),
        ("fri 2pm", "Fri, Nov 20 at 2:00 PM"),
        ("dec 3 9am", "Thu, Dec 3 at 9:00 AM"),
        // No time of day: 7am.
        ("friday", "Fri, Nov 20 at 7:00 AM"),
    ])
    func typedTimes(text: String, expected: String) {
        #expect(Self.describe(SnoozeTime.parse(text, now: Self.wednesday(10), calendar: Self.calendar)) == expected, "\(text)")
    }

    /// Nothing understood, a time already past, and nonsense counts give nothing.
    @Test(arguments: ["", "   ", "banana", "in 0 hours", "in 5000 days", "in many days", "today 9am", "feb 30", "fri 2", "tomorrow 3", "13pm", "25:00",
                     // A word amount needs a unit; nothing over 1000.
                     "five", "a", "1001", "0", "0m", "5 fortnights", "5 ms"])
    func notUnderstood(text: String) {
        #expect(SnoozeTime.parse(text, now: Self.wednesday(10), calendar: Self.calendar) == nil, "\(text)")
    }

    /// Every spelling of every unit, with and without a space, with "in", in any case (David,
    /// 2026-11-20 evening: "all the permutations"), generated from the parser's own table.
    @Test func everyUnitSpelling() {
        let now = Self.wednesday(10)
        let cal = Self.calendar
        func sevenAM(_ component: Calendar.Component, _ value: Int) -> Date {
            cal.date(bySettingHour: 7, minute: 0, second: 0, of: cal.date(byAdding: component, value: value, to: cal.startOfDay(for: now))!)!
        }
        let expected: [SnoozeTime.Unit: Date] = [
            .minute: cal.date(byAdding: .minute, value: 5, to: now)!,
            .hour: cal.date(byAdding: .hour, value: 5, to: now)!,
            .day: sevenAM(.day, 5),
            .week: sevenAM(.day, 35),
            .month: sevenAM(.month, 5),
            .year: sevenAM(.year, 5),
        ]
        #expect(Set(SnoozeTime.unitSpellings.keys) == Set(SnoozeTime.Unit.allCases))
        var checked = 0
        for (unit, spellings) in SnoozeTime.unitSpellings {
            for spelling in spellings {
                for form in ["5\(spelling)", "5 \(spelling)", "in 5 \(spelling)", "in 5\(spelling)", "5 \(spelling.uppercased())", "In 5 \(spelling.capitalized)", " 5 \(spelling) "] {
                    #expect(SnoozeTime.parse(form, now: now, calendar: cal) == expected[unit], "\(form)")
                    checked += 1
                }
            }
        }
        #expect(checked == 27 * 7)
        // m is minutes, mo is months.
        #expect(SnoozeTime.parse("5m", now: now, calendar: cal) == expected[.minute])
        #expect(SnoozeTime.parse("5mo", now: now, calendar: cal) == expected[.month])
    }

    /// A number alone is minutes; word amounts take a unit with or without "in"; morning is
    /// tomorrow 7am. Wednesday 10am.
    @Test(arguments: [
        ("5", "Wed, Nov 18 at 10:05 AM"),
        ("90", "Wed, Nov 18 at 11:30 AM"),
        ("in 5", "Wed, Nov 18 at 10:05 AM"),
        ("two weeks", "Wed, Dec 2 at 7:00 AM"),
        ("an hour", "Wed, Nov 18 at 11:00 AM"),
        ("morning", "Thu, Nov 19 at 7:00 AM"),
        ("Morning", "Thu, Nov 19 at 7:00 AM"),
        ("3pm", "Wed, Nov 18 at 3:00 PM"),
    ])
    func numbersAndMorning(text: String, expected: String) {
        #expect(Self.describe(SnoozeTime.parse(text, now: Self.wednesday(10), calendar: Self.calendar)) == expected, "\(text)")
    }

    /// A month or year onto a day the target month lacks lands on its last day, at 7am.
    @Test func monthEndsClamp() {
        let cal = Self.calendar
        func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))! }
        #expect(SnoozeTime.parse("1 month", now: day(2027, 1, 31), calendar: cal) == day(2027, 2, 28, 7))
        #expect(SnoozeTime.parse("1mo", now: day(2028, 1, 31), calendar: cal) == day(2028, 2, 29, 7))
        #expect(SnoozeTime.parse("1y", now: day(2028, 2, 29), calendar: cal) == day(2029, 2, 28, 7))
        #expect(SnoozeTime.parse("3 months", now: day(2026, 11, 30), calendar: cal) == day(2027, 2, 28, 7))
    }

    /// Friday 2026-11-20 at the given time, New York.
    static func friday(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: hour, minute: minute))!
    }

    /// Typed days and times are worked out from the given now, never the real clock
    /// (David, 2026-11-20: on a Friday "fri 2pm" gave next Friday).
    static let againstNow: [(String, Date, String)] = [
        // A weekday is today while its time is ahead, else next week's.
        ("fri 2pm", friday(9), "Fri, Nov 20 at 2:00 PM"),
        ("fri 2pm", friday(15), "Fri, Nov 27 at 2:00 PM"),
        ("friday", friday(6), "Fri, Nov 20 at 7:00 AM"),
        ("friday", friday(9), "Fri, Nov 27 at 7:00 AM"),
        ("mon 9:30am", friday(9), "Mon, Nov 23 at 9:30 AM"),
        ("tues at 14:00", friday(9), "Tue, Nov 24 at 2:00 PM"),
        // A month-day still ahead this year, or next year's.
        ("dec 3 9am", friday(9), "Thu, Dec 3 at 9:00 AM"),
        ("december 3rd, 9am", friday(9), "Thu, Dec 3 at 9:00 AM"),
        ("12/3", friday(9), "Thu, Dec 3 at 7:00 AM"),
        ("nov 1 9am", friday(9), "Mon, Nov 1 at 9:00 AM"),
        // A time alone: today, or tomorrow once past.
        ("3pm", friday(9), "Fri, Nov 20 at 3:00 PM"),
        ("8am", friday(9), "Sat, Nov 21 at 8:00 AM"),
        ("noon", friday(9), "Fri, Nov 20 at 12:00 PM"),
        ("midnight", friday(9), "Sat, Nov 21 at 12:00 AM"),
        ("today 5pm", friday(9), "Fri, Nov 20 at 5:00 PM"),
        ("tomorrow noon", friday(9), "Sat, Nov 21 at 12:00 PM"),
    ]

    @Test func typedDaysAndTimesFollowNow() {
        for (text, now, expected) in Self.againstNow {
            #expect(Self.describe(SnoozeTime.parse(text, now: now, calendar: Self.calendar)) == expected, "\(text)")
        }
        // A month-day already past this year is next year's.
        let nextYear = SnoozeTime.parse("nov 1 9am", now: Self.friday(9), calendar: Self.calendar)
        #expect(nextYear.map { Self.calendar.component(.year, from: $0) } == 2027)
        // The prompt's own words still win: "tomorrow" alone is the preset.
        #expect(Self.describe(SnoozeTime.parse("tomorrow", now: Self.friday(9), calendar: Self.calendar)) == "Sat, Nov 21 at 7:00 AM")
    }

    /// Saturday after 7am: "this weekend" is the next Saturday; Monday after 7am: "next week"
    /// is the Monday after.
    @Test func weekendAndNextWeekLookAhead() {
        let saturday = Self.calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 9))!
        let weekend = SnoozeTime.presets.first { $0.name == "this weekend" }!
        #expect(Self.describe(SnoozeTime.date(of: weekend, now: saturday, calendar: Self.calendar)) == "Sat, Nov 28 at 7:00 AM")
        let monday = Self.calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 9))!
        let nextWeek = SnoozeTime.presets.first { $0.name == "next week" }!
        #expect(Self.describe(SnoozeTime.date(of: nextWeek, now: monday, calendar: Self.calendar)) == "Mon, Nov 30 at 7:00 AM")
    }
}
