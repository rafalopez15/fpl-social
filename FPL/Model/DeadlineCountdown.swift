//
//  DeadlineCountdown.swift
//  FPL
//

import Foundation

/// The next transfer deadline and how long is left, for the Gameweek tab's header.
struct DeadlineCountdown: Equatable {
    let gameweek: Int
    let deadline: Date

    /// The first deadline still to come. Nil after the season's last one.
    static func next(in events: [Event], now: Date = .now) -> DeadlineCountdown? {
        events.filter { $0.deadlineTime > now }
            .min { $0.deadlineTime < $1.deadlineTime }
            .map { DeadlineCountdown(gameweek: $0.id, deadline: $0.deadlineTime) }
    }

    /// Under a day left.
    func isSoon(now: Date = .now) -> Bool {
        deadline.timeIntervalSince(now) < 24 * 60 * 60
    }

    /// "1d 17h", then "5h 12m" under a day, then "42m" under an hour.
    func remaining(now: Date = .now) -> String {
        let minutes = max(0, Int(deadline.timeIntervalSince(now)) / 60)
        let (days, hours) = (minutes / 1440, minutes % 1440 / 60)
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        return minutes > 0 ? "\(minutes)m" : "<1m"
    }

    /// "Gameweek 10 deadline · Fri, Nov 6 at 1:30 PM · 1d 17h", in the user's locale.
    func text(now: Date = .now, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        "Gameweek \(gameweek) deadline · \(date(timeZone, locale)) · \(remaining(now: now))"
    }

    /// For VoiceOver: "Gameweek 10 deadline Fri, Nov 6 at 1:30 PM, in 1 day, 17 hours".
    func spokenText(now: Date = .now, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        let left = Duration.seconds(max(60, deadline.timeIntervalSince(now)))
        let units: Set<Duration.UnitsFormatStyle.Unit> = isSoon(now: now) ? [.hours, .minutes] : [.days, .hours]
        let spoken = left.formatted(.units(allowed: units, width: .wide, maximumUnitCount: 2,
                                           fractionalPart: .hide(rounded: .down)).locale(locale))
        return "Gameweek \(gameweek) deadline \(date(timeZone, locale)), in \(spoken)"
    }

    private func date(_ timeZone: TimeZone, _ locale: Locale) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()
        style.timeZone = timeZone
        style.locale = locale
        return deadline.formatted(style)
    }
}
