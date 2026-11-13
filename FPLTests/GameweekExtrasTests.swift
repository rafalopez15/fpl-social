//
//  GameweekExtrasTests.swift
//  FPLTests
//

import Foundation
import Testing
@testable import FPL

/// The Gameweek tab around its matches: your players in a match, a team's next
/// fixtures and the deadline countdown.
@MainActor
struct GameweekExtrasTests {
    private typealias Base = GameweekFixturesTests

    // MARK: Deadline countdown

    static func event(_ id: Int, deadline: Date) -> Event {
        Event(id: id, name: "Gameweek \(id)", deadlineTime: deadline, finished: false, isCurrent: false, isNext: false)
    }

    @Test func theCountdownShortensItsUnitsAsTheDeadlineNears() {
        let countdown = DeadlineCountdown(gameweek: 10, deadline: Base.time(day: 6, hour: 13, minute: 30))
        func left(day: Int, hour: Int, minute: Int = 0) -> String {
            countdown.remaining(now: Base.time(day: day, hour: hour, minute: minute))
        }
        #expect(left(day: 4, hour: 20, minute: 30) == "1d 17h")
        #expect(left(day: 5, hour: 13, minute: 30) == "1d 0h")
        #expect(left(day: 5, hour: 13, minute: 31) == "23h 59m")
        #expect(left(day: 6, hour: 8, minute: 18) == "5h 12m")
        #expect(left(day: 6, hour: 12, minute: 30) == "1h 0m")
        #expect(left(day: 6, hour: 12, minute: 48) == "42m")
        #expect(countdown.remaining(now: countdown.deadline - 30) == "<1m")
    }

    @Test func theCountdownWarnsUnderADay() {
        let countdown = DeadlineCountdown(gameweek: 10, deadline: Base.time(day: 6, hour: 13, minute: 30))
        #expect(!countdown.isSoon(now: Base.time(day: 5, hour: 13, minute: 30)))
        #expect(countdown.isSoon(now: Base.time(day: 5, hour: 13, minute: 31)))
    }

    @Test func theCountdownMovesToTheNextDeadlineAndEndsWithTheSeason() {
        let events = [Self.event(10, deadline: Base.time(day: 6, hour: 13, minute: 30)),
                      Self.event(11, deadline: Base.time(day: 21, hour: 11)),
                      Self.event(9, deadline: Base.time(day: 1, hour: 11))]
        #expect(DeadlineCountdown.next(in: events, now: Base.time(day: 4, hour: 9))?.gameweek == 10)
        // At the deadline itself it's passed.
        #expect(DeadlineCountdown.next(in: events, now: Base.time(day: 6, hour: 13, minute: 30))?.gameweek == 11)
        #expect(DeadlineCountdown.next(in: events, now: Base.time(day: 21, hour: 11)) == nil)
        #expect(DeadlineCountdown.next(in: [], now: Base.time(day: 4, hour: 9)) == nil)
    }

    @Test func theCountdownsLineAndVoiceOverText() {
        let countdown = DeadlineCountdown(gameweek: 10, deadline: Base.time(day: 6, hour: 13, minute: 30))
        let us = Locale(identifier: "en_US")
        let text = countdown.text(now: Base.time(day: 4, hour: 20, minute: 30), timeZone: Base.utc, locale: us)
        #expect(text.hasPrefix("Gameweek 10 deadline · Fri, Nov 6"))
        #expect(text.contains("1:30") && text.hasSuffix(" · 1d 17h"))

        let spoken = countdown.spokenText(now: Base.time(day: 4, hour: 20, minute: 30), timeZone: Base.utc, locale: us)
        #expect(spoken.hasSuffix(", in 1 day, 17 hours"))
        let soon = countdown.spokenText(now: Base.time(day: 6, hour: 8, minute: 18), timeZone: Base.utc, locale: us)
        #expect(soon.hasSuffix(", in 5 hours, 12 minutes"))
    }
}
