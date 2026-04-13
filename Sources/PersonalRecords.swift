//
//  PersonalRecords.swift
//  StatsPlugin
//
//  Lightweight rolling personal-best tracker. Stores three records
//  (turns, focus minutes, lines written) in UserDefaults keyed by
//  the date they were set. Used by the editorial header to surface
//  "a record-breaking day" and by the ticker for background context.
//

import Foundation

struct PersonalRecords: Sendable {
    let maxTurns: Int
    let maxTurnsDate: Date?
    let maxFocusMinutes: Int
    let maxFocusDate: Date?
    let maxLinesWritten: Int
    let maxLinesDate: Date?

    /// Records for the day that was just finalized (before today's data is applied).
    static func load() -> PersonalRecords {
        let ud = UserDefaults.standard
        return PersonalRecords(
            maxTurns: ud.integer(forKey: "stats.pr.maxTurns"),
            maxTurnsDate: ud.object(forKey: "stats.pr.maxTurnsDate") as? Date,
            maxFocusMinutes: ud.integer(forKey: "stats.pr.maxFocus"),
            maxFocusDate: ud.object(forKey: "stats.pr.maxFocusDate") as? Date,
            maxLinesWritten: ud.integer(forKey: "stats.pr.maxLines"),
            maxLinesDate: ud.object(forKey: "stats.pr.maxLinesDate") as? Date
        )
    }

    /// Result of checking a freshly computed day against the records.
    struct Check: Sendable {
        let brokeTurns: Bool
        let brokeFocus: Bool
        let brokeLines: Bool
        var anyBroken: Bool { brokeTurns || brokeFocus || brokeLines }
    }

    /// Compare the given report against the stored records. Does NOT update.
    static func check(day: DailyReport) -> Check {
        let pr = load()
        return Check(
            brokeTurns: day.turnCount > pr.maxTurns,
            brokeFocus: day.focusMinutes > pr.maxFocusMinutes,
            brokeLines: day.linesWritten > pr.maxLinesWritten
        )
    }

    /// Update stored records if this day beats any of them. Idempotent —
    /// safe to call every time the view loads.
    static func updateIfBroken(day: DailyReport) {
        let ud = UserDefaults.standard
        let pr = load()
        if day.turnCount > pr.maxTurns {
            ud.set(day.turnCount, forKey: "stats.pr.maxTurns")
            ud.set(day.date, forKey: "stats.pr.maxTurnsDate")
        }
        if day.focusMinutes > pr.maxFocusMinutes {
            ud.set(day.focusMinutes, forKey: "stats.pr.maxFocus")
            ud.set(day.date, forKey: "stats.pr.maxFocusDate")
        }
        if day.linesWritten > pr.maxLinesWritten {
            ud.set(day.linesWritten, forKey: "stats.pr.maxLines")
            ud.set(day.date, forKey: "stats.pr.maxLinesDate")
        }
    }
}
