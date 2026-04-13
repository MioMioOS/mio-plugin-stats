//
//  DailyReport.swift
//  StatsPlugin
//
//  Aggregated "what did Claude do for you yesterday" numbers, computed once
//  a day from the per-session JSONL files under ~/.claude/projects/.
//

import Foundation

struct DailyReport: Equatable, Sendable, Codable {
    let date: Date
    let sessionCount: Int
    let turnCount: Int
    let focusMinutes: Int
    let toolCounts: [String: Int]
    let skillCounts: [String: Int]
    let mcpServerCounts: [String: Int]
    let linesWritten: Int
    let primaryProjectName: String?
    let projectCount: Int
    let peakBurstMinutes: Int
    let filesEdited: Int
    let peakHour: Int?

    // NEW — editorial enhancements
    /// First user-turn timestamp of the day (local). Nil on quiet days.
    let firstActivity: Date?
    /// Last user-turn timestamp of the day (local). Nil on quiet days.
    let lastActivity: Date?
    /// Number of "flow blocks" — contiguous focus segments ≥ 15 minutes
    /// where adjacent turns are ≤ 2 minutes apart. Lower-bound for
    /// real deep work, stricter than the raw focusMinutes aggregate.
    let flowBlockCount: Int
    /// Longest flow-block duration in minutes (≥ 15m threshold applied
    /// to entries; peakBurstMinutes uses the looser 5-min gap rule).
    let longestFlowBlockMinutes: Int
    /// Per-project focus minutes. Sum equals focusMinutes (approximately).
    let projectTimes: [String: Int]

    var hasActivity: Bool {
        sessionCount > 0 && turnCount > 0
    }

    static func empty(date: Date) -> DailyReport {
        DailyReport(
            date: date,
            sessionCount: 0,
            turnCount: 0,
            focusMinutes: 0,
            toolCounts: [:],
            skillCounts: [:],
            mcpServerCounts: [:],
            linesWritten: 0,
            primaryProjectName: nil,
            projectCount: 0,
            peakBurstMinutes: 0,
            filesEdited: 0,
            peakHour: nil,
            firstActivity: nil,
            lastActivity: nil,
            flowBlockCount: 0,
            longestFlowBlockMinutes: 0,
            projectTimes: [:]
        )
    }
}

// MARK: - Weekly aggregate

struct WeeklyReport: Equatable, Sendable, Codable {
    let days: [DailyReport]
    let turnCount: Int
    let focusMinutes: Int
    let linesWritten: Int
    let sessionCount: Int
    let filesEdited: Int
    let projectCount: Int
    let toolCounts: [String: Int]
    let skillCounts: [String: Int]
    let mcpServerCounts: [String: Int]
    let peakBurstMinutes: Int
    let peakBurstDate: Date?
    let peakDay: DailyReport?
    let primaryProjectName: String?
    let streak: Int

    // NEW
    let firstActivity: Date?
    let lastActivity: Date?
    let flowBlockCount: Int
    let longestFlowBlockMinutes: Int
    let projectTimes: [String: Int]

    var hasActivity: Bool { turnCount > 0 }

    static func aggregate(_ days: [DailyReport]) -> WeeklyReport {
        let turns = days.reduce(0) { $0 + $1.turnCount }
        let focus = days.reduce(0) { $0 + $1.focusMinutes }
        let lines = days.reduce(0) { $0 + $1.linesWritten }
        let sessions = days.reduce(0) { $0 + $1.sessionCount }
        let files = days.reduce(0) { $0 + $1.filesEdited }

        var tools: [String: Int] = [:]
        var skills: [String: Int] = [:]
        var mcps: [String: Int] = [:]
        var projectTurnSum: [String: Int] = [:]
        var projectTimeSum: [String: Int] = [:]
        var allProjects = Set<String>()
        var peakBurst = 0
        var peakBurstDate: Date?
        var peakDay: DailyReport?
        var flowBlocks = 0
        var longestFlow = 0
        var firstActivity: Date?
        var lastActivity: Date?

        for d in days {
            for (k, v) in d.toolCounts  { tools[k, default: 0] += v }
            for (k, v) in d.skillCounts { skills[k, default: 0] += v }
            for (k, v) in d.mcpServerCounts { mcps[k, default: 0] += v }
            for (k, v) in d.projectTimes { projectTimeSum[k, default: 0] += v }
            if let p = d.primaryProjectName {
                projectTurnSum[p, default: 0] += d.turnCount
                allProjects.insert(p)
            }
            if d.peakBurstMinutes > peakBurst {
                peakBurst = d.peakBurstMinutes
                peakBurstDate = d.date
            }
            if peakDay == nil || d.turnCount > (peakDay?.turnCount ?? 0) {
                peakDay = d
            }
            flowBlocks += d.flowBlockCount
            if d.longestFlowBlockMinutes > longestFlow {
                longestFlow = d.longestFlowBlockMinutes
            }
            if let f = d.firstActivity, firstActivity == nil || f < firstActivity! {
                firstActivity = f
            }
            if let l = d.lastActivity, lastActivity == nil || l > lastActivity! {
                lastActivity = l
            }
        }

        var streak = 0
        for d in days.reversed() {
            if d.hasActivity { streak += 1 } else { break }
        }

        return WeeklyReport(
            days: days,
            turnCount: turns,
            focusMinutes: focus,
            linesWritten: lines,
            sessionCount: sessions,
            filesEdited: files,
            projectCount: allProjects.count,
            toolCounts: tools,
            skillCounts: skills,
            mcpServerCounts: mcps,
            peakBurstMinutes: peakBurst,
            peakBurstDate: peakBurstDate,
            peakDay: (peakDay?.hasActivity == true) ? peakDay : nil,
            primaryProjectName: projectTurnSum.max { $0.value < $1.value }?.key,
            streak: streak,
            firstActivity: firstActivity,
            lastActivity: lastActivity,
            flowBlockCount: flowBlocks,
            longestFlowBlockMinutes: longestFlow,
            projectTimes: projectTimeSum
        )
    }
}
