//
//  StatsView.swift
//  StatsPlugin
//
//  Newspaper / magazine layout:
//    Masthead  |  Headline + Deck  |  Stat Strip  |
//    Two-column body (narrative + data table)     |
//    Breakdown boxes (Tools / Skills / MCP)       |
//    Rhythm (week) / Highlights (week)            |
//    Editor's Note (optional)
//

import SwiftUI

struct StatsView: View {
    @ObservedObject private var analytics = AnalyticsCollector.shared
    @ObservedObject private var notes = EditorsNoteService.shared
    @State private var mode: Mode = .day
    @State private var didTriggerNote = false

    private static let lime = Color(red: 0xCA / 255.0, green: 0xFF / 255.0, blue: 0x00 / 255.0)
    private static let ink = Color.white

    enum Mode { case day, week }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if !analytics.hasLoadedOnce {
                loadingState
            } else if let week = analytics.thisWeek, week.hasActivity {
                content(week: week, lastWeek: analytics.lastWeek)
                    .onAppear {
                        if didTriggerNote { return }
                        didTriggerNote = true
                        if let yesterday = week.days.last {
                            PersonalRecords.updateIfBroken(day: yesterday)
                            if notes.isEnabled {
                                // Trigger the note for the current mode only.
                                // Switching modes will lazy-trigger the other one.
                                if mode == .day {
                                    notes.loadOrGenerateDay(for: yesterday)
                                } else {
                                    notes.loadOrGenerateWeek(for: week, lastWeek: analytics.lastWeek)
                                }
                            }
                        }
                    }
            } else {
                noDataState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty states

    private var loadingState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 60)
            ProgressView().scaleEffect(0.7)
            Text(L10n.s("state.loading"))
                .font(.system(size: 11))
                .foregroundColor(Self.ink.opacity(0.45))
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }

    private var noDataState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 60)
            Text(L10n.s("state.empty"))
                .font(.system(size: 22, weight: .medium, design: .serif))
                .italic()
                .foregroundColor(Self.ink.opacity(0.6))
            Text(L10n.s("state.emptyHint"))
                .font(.system(size: 11))
                .foregroundColor(Self.ink.opacity(0.3))
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Main content

    @ViewBuilder
    private func content(week: WeeklyReport, lastWeek: WeeklyReport?) -> some View {
        let yesterday = week.days.last ?? DailyReport.empty(date: Date())
        let isDay = mode == .day

        VStack(alignment: .leading, spacing: 0) {
            // 1. Masthead
            masthead(week: week, yesterday: yesterday, isDay: isDay)
                .padding(.top, 14)

            thickRule.padding(.top, 8)
            thinRule.padding(.top, 2)
            Spacer().frame(height: 22)

            // 2. Headline + deck
            headlineBlock(week: week, yesterday: yesterday, isDay: isDay)
                .padding(.horizontal, 20)
                .padding(.bottom, 22)

            // 3. Stat strip (4-column bordered band)
            statStrip(week: week, yesterday: yesterday, isDay: isDay)
                .padding(.horizontal, 16)
                .padding(.bottom, 22)

            // 4. Two-column body: left narrative, right data sheet
            twoColumnBody(week: week, yesterday: yesterday, isDay: isDay, lastWeek: lastWeek)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)

            // 5. Week-only rhythm + highlights
            if !isDay {
                sectionRule(L10n.s("section.rhythm"))
                weekRhythm(week: week)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                let highlights = weekHighlightLines(week: week, lastWeek: lastWeek)
                if !highlights.isEmpty {
                    sectionRule(L10n.s("section.highlights"))
                    highlightList(highlights)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }
            }

            // 6. Breakdowns — 3 bordered columns
            let breakdowns = breakdownSections(week: week, yesterday: yesterday, isDay: isDay)
            if !breakdowns.isEmpty {
                sectionRule(L10n.isChinese ? "细分" : "BREAKDOWN")
                breakdownColumns(breakdowns)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
            }

            // 7. Editor's Note (optional)
            if notes.isEnabled || !notes.consentAsked {
                sectionRule(L10n.s("note.title"))
                editorsNoteBox(for: yesterday)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }

            // Bottom thick rule closure
            thickRule.padding(.top, 8)
            Spacer().frame(height: 16)
        }
        .animation(.easeInOut(duration: 0.25), value: mode)
    }

    // MARK: - Masthead

    @ViewBuilder
    private func masthead(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> some View {
        VStack(spacing: 6) {
            thickRule

            HStack {
                Text(Self.paperTitle)
                    .font(.system(size: 11, weight: .black, design: .serif))
                    .tracking(2)
                    .foregroundColor(Self.ink.opacity(0.9))

                Spacer()

                modeToggle
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            thinRule

            HStack {
                Text(volumeLine(week: week, yesterday: yesterday, isDay: isDay))
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1.4)
                    .foregroundColor(Self.ink.opacity(0.5))
                Spacer()
                Text(Self.tagline)
                    .font(.system(size: 8, weight: .medium, design: .serif))
                    .italic()
                    .foregroundColor(Self.ink.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private static let paperTitle: String = L10n.isChinese
        ? "代码岛时报"
        : "THE CODE ISLAND DAILY"

    private static let tagline: String = L10n.isChinese
        ? "带着意图工作"
        : "\"WORK WITH INTENTION\""

    private func volumeLine(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> String {
        let cal = Calendar.current
        let doy = cal.ordinality(of: .day, in: .year, for: yesterday.date) ?? 0
        let issue = "VOL. I  ·  NO. \(doy)"
        let date: String
        if isDay {
            date = L10n.dayDate(yesterday.date).uppercased()
        } else {
            let start = week.days.first?.date ?? yesterday.date
            date = L10n.weekRange(start, yesterday.date).uppercased()
        }
        return "\(issue)  ·  \(date)"
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeButton(L10n.s("mode.day"), active: mode == .day) {
                mode = .day
                lazyTriggerNote()
            }
            modeButton(L10n.s("mode.week"), active: mode == .week) {
                mode = .week
                lazyTriggerNote()
            }
        }
        .padding(2)
        .background(Capsule().fill(Self.ink.opacity(0.05)))
    }

    /// Trigger the editor's note for the current mode if it isn't
    /// already loaded/loading. Called when user switches modes.
    private func lazyTriggerNote() {
        guard notes.isEnabled, let week = analytics.thisWeek,
              let yesterday = week.days.last else { return }
        let scope: EditorsNoteService.Scope = mode == .day ? .day : .week
        let current = notes.state(for: scope)
        switch current {
        case .idle, .error:
            if scope == .day {
                notes.loadOrGenerateDay(for: yesterday)
            } else {
                notes.loadOrGenerateWeek(for: week, lastWeek: analytics.lastWeek)
            }
        default:
            break
        }
    }

    private func modeButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: active ? .semibold : .medium))
                .foregroundColor(active ? .black : Self.ink.opacity(0.55))
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(Capsule().fill(active ? Self.lime : Color.clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rules

    private var thickRule: some View {
        Rectangle()
            .fill(Self.ink.opacity(0.4))
            .frame(height: 1.5)
            .frame(maxWidth: .infinity)
    }

    private var thinRule: some View {
        Rectangle()
            .fill(Self.ink.opacity(0.15))
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
    }

    /// Small-caps section label with thin rules above and below — used
    /// like a newspaper cross-head.
    @ViewBuilder
    private func sectionRule(_ label: String) -> some View {
        VStack(spacing: 4) {
            thinRule
            HStack {
                Spacer()
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(2.5)
                    .foregroundColor(Self.ink.opacity(0.45))
                Spacer()
            }
            .padding(.vertical, 4)
            thinRule
        }
    }

    // MARK: - Headline + deck

    private func headlineBlock(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> some View {
        let (headline, deck) = headlineAndDeck(week: week, yesterday: yesterday, isDay: isDay)
        return VStack(alignment: .leading, spacing: 10) {
            Text(headline)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .italic()
                .foregroundColor(Self.ink.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            Text(deck)
                .font(.system(size: 14, weight: .regular, design: .serif))
                .italic()
                .foregroundColor(Self.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headlineAndDeck(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> (String, String) {
        let hl = headlineText(week: week, yesterday: yesterday, isDay: isDay)

        // Deck = a short "subtitle" paragraph that teases the main numbers
        if isDay {
            let focusStr = Self.humanMinutes(yesterday.focusMinutes)
            let turns = yesterday.turnCount
            let deck: String
            if L10n.isChinese {
                deck = "\(turns) 次活跃互动, \(focusStr) 不间断专注"
            } else {
                deck = "\(turns) active turns, \(focusStr) of uninterrupted focus"
            }
            return (hl, deck)
        } else {
            let focusStr = Self.humanMinutes(week.focusMinutes)
            let active = week.days.filter(\.hasActivity).count
            let deck: String
            if L10n.isChinese {
                deck = "\(active) 天活跃, 总计 \(focusStr) 的专注时长"
            } else {
                deck = "\(active) active days, \(focusStr) of focused work"
            }
            return (hl, deck)
        }
    }

    private func headlineText(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> String {
        if isDay {
            let record = PersonalRecords.check(day: yesterday)
            if record.anyBroken { return L10n.s("hl.record") }

            let turns = yesterday.turnCount
            let focus = yesterday.focusMinutes
            let toolSum = yesterday.toolCounts.values.reduce(0, +)
            let digCount = (yesterday.toolCounts["Bash"] ?? 0)
                + (yesterday.toolCounts["Grep"] ?? 0)
                + (yesterday.toolCounts["Read"] ?? 0)
            let digRatio = toolSum > 0 ? Double(digCount) / Double(toolSum) : 0
            let lpt = turns > 0 ? Double(yesterday.linesWritten) / Double(turns) : 0

            if digRatio >= 0.6 && turns >= 30 { return L10n.s("hl.debugging") }
            if lpt >= 3 && yesterday.linesWritten > 100 { return L10n.s("hl.shipping") }
            if lpt <= 0.5 && turns >= 30 { return L10n.s("hl.exploring") }
            if let hour = yesterday.peakHour, (hour >= 22 || hour < 5) { return L10n.s("hl.night") }
            if yesterday.projectCount >= 3 { return L10n.s("hl.multi") }
            if focus >= 180 && turns >= 80 { return L10n.s("hl.deepDay") }
            if focus >= 60 && turns >= 20 { return L10n.s("hl.steady") }
            if focus < 60 && turns > 0 { return L10n.s("hl.fragmented") }
            return L10n.s("hl.quietDay")
        } else {
            let active = week.days.filter(\.hasActivity).count
            if week.focusMinutes >= 600 && active >= 5 { return L10n.s("hl.weekProductive") }
            let maxDay = week.days.map(\.turnCount).max() ?? 0
            let concentration = week.turnCount > 0 ? Double(maxDay) / Double(week.turnCount) : 0
            if concentration >= 0.5 { return L10n.s("hl.weekUneven") }
            if active >= 4 { return L10n.s("hl.weekSteady") }
            return L10n.s("hl.weekQuiet")
        }
    }

    // MARK: - Stat strip (4-column bordered band)

    private func statStrip(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> some View {
        let focusStr: String = {
            let mins = isDay ? yesterday.focusMinutes : week.focusMinutes
            let h = mins / 60
            let m = mins % 60
            return String(format: "%d:%02d", h, m)
        }()
        let turns = isDay ? yesterday.turnCount : week.turnCount
        let flow = isDay ? yesterday.flowBlockCount : week.flowBlockCount
        let lines = isDay ? yesterday.linesWritten : week.linesWritten

        return VStack(spacing: 0) {
            thinRule
            HStack(spacing: 0) {
                statCell(label: L10n.isChinese ? "专注" : "FOCUS", value: focusStr)
                statDivider
                statCell(label: L10n.isChinese ? "互动" : "TURNS", value: "\(turns)")
                statDivider
                statCell(label: L10n.isChinese ? "心流" : "FLOW", value: "\(flow)")
                statDivider
                statCell(label: L10n.isChinese ? "代码行" : "LINES", value: "\(lines)")
            }
            .padding(.vertical, 14)
            thinRule
        }
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1.8)
                .foregroundColor(Self.ink.opacity(0.45))
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(Self.ink.opacity(0.95))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Self.ink.opacity(0.12))
            .frame(width: 0.5, height: 40)
    }

    // MARK: - Two-column body

    @ViewBuilder
    private func twoColumnBody(week: WeeklyReport, yesterday: DailyReport, isDay: Bool, lastWeek: WeeklyReport?) -> some View {
        HStack(alignment: .top, spacing: 18) {
            // Left: narrative / insight
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.isChinese ? "叙述" : "THE STORY")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.8)
                    .foregroundColor(Self.ink.opacity(0.42))
                bodyStyled(bodyText(week: week, yesterday: yesterday, isDay: isDay, lastWeek: lastWeek))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Vertical rule separator
            Rectangle()
                .fill(Self.ink.opacity(0.12))
                .frame(width: 0.5)

            // Right: data sheet (key/value table)
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.isChinese ? "数据" : "BY THE NUMBERS")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.8)
                    .foregroundColor(Self.ink.opacity(0.42))
                dataSheet(week: week, yesterday: yesterday, isDay: isDay)
            }
            .frame(width: 180, alignment: .leading)
        }
    }

    // MARK: - Data sheet (right column of two-column body)

    @ViewBuilder
    private func dataSheet(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let rows = dataSheetRows(week: week, yesterday: yesterday, isDay: isDay)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Self.ink.opacity(0.5))
                    Spacer(minLength: 4)
                    Text(row.1)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Self.ink.opacity(0.85))
                }
            }
        }
    }

    private func dataSheetRows(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> [(String, String)] {
        var rows: [(String, String)] = []
        if isDay {
            rows.append((L10n.isChinese ? "会话数" : "sessions", "\(yesterday.sessionCount)"))
            rows.append((L10n.isChinese ? "项目数" : "projects", "\(yesterday.projectCount)"))
            if let p = yesterday.primaryProjectName {
                rows.append((L10n.isChinese ? "主项目" : "primary", truncate(p, 12)))
            }
            if yesterday.longestFlowBlockMinutes > 0 {
                rows.append((L10n.isChinese ? "最长专注" : "longest", "\(yesterday.longestFlowBlockMinutes)m"))
            }
            if let h = yesterday.peakHour {
                rows.append((L10n.isChinese ? "高峰时段" : "peak hour", String(format: "%02d:00", h)))
            }
            if let first = yesterday.firstActivity, let last = yesterday.lastActivity {
                rows.append((L10n.isChinese ? "工作窗口" : "window",
                             "\(L10n.clockTime(first))–\(L10n.clockTime(last))"))
            }
            if yesterday.filesEdited > 0 {
                rows.append((L10n.isChinese ? "文件数" : "files", "\(yesterday.filesEdited)"))
            }
        } else {
            let active = week.days.filter(\.hasActivity).count
            rows.append((L10n.isChinese ? "活跃天数" : "active days", "\(active) / 7"))
            rows.append((L10n.isChinese ? "会话数" : "sessions", "\(week.sessionCount)"))
            rows.append((L10n.isChinese ? "项目数" : "projects", "\(week.projectCount)"))
            if let p = week.primaryProjectName {
                rows.append((L10n.isChinese ? "主项目" : "primary", truncate(p, 12)))
            }
            if week.longestFlowBlockMinutes > 0 {
                rows.append((L10n.isChinese ? "最长专注" : "longest", "\(week.longestFlowBlockMinutes)m"))
            }
            rows.append((L10n.isChinese ? "心流段数" : "flow blocks", "\(week.flowBlockCount)"))
            if week.filesEdited > 0 {
                rows.append((L10n.isChinese ? "文件数" : "files", "\(week.filesEdited)"))
            }
            if week.streak > 0 {
                rows.append((L10n.isChinese ? "连续天数" : "streak", "\(week.streak)"))
            }
        }
        return rows
    }

    private func truncate(_ str: String, _ maxLen: Int) -> String {
        if str.count <= maxLen { return str }
        return String(str.prefix(maxLen)) + "…"
    }

    // MARK: - Body text (used by The Story column)

    private func bodyStyled(_ text: String) -> some View {
        var parts: [(String, Bool)] = []
        var remaining = text
        while let openRange = remaining.range(of: "<hi>") {
            let before = String(remaining[remaining.startIndex..<openRange.lowerBound])
            if !before.isEmpty { parts.append((before, false)) }
            remaining = String(remaining[openRange.upperBound...])
            if let closeRange = remaining.range(of: "</hi>") {
                let highlighted = String(remaining[remaining.startIndex..<closeRange.lowerBound])
                parts.append((highlighted, true))
                remaining = String(remaining[closeRange.upperBound...])
            }
        }
        if !remaining.isEmpty { parts.append((remaining, false)) }

        var result = Text("")
        for (chunk, hi) in parts {
            let t = Text(chunk)
                .font(.system(size: 13, weight: hi ? .semibold : .regular, design: .serif))
                .foregroundColor(hi ? Self.lime : Self.ink.opacity(0.78))
            result = result + t
        }
        return result
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bodyText(week: WeeklyReport, yesterday: DailyReport, isDay: Bool, lastWeek: WeeklyReport?) -> String {
        if isDay {
            if let insight = smartInsight(yesterday: yesterday, week: week, lastWeek: lastWeek) {
                return insight
            }
            if yesterday.projectTimes.count >= 2 {
                let sorted = yesterday.projectTimes.sorted { $0.value > $1.value }.prefix(3)
                return sorted.map { "<hi>\(Self.formatMinutes($0.value))</hi> \(L10n.isChinese ? "在" : "on") \($0.key)" }
                    .joined(separator: L10n.isChinese ? "  ·  " : "  ·  ")
            }
            let turns = yesterday.turnCount
            let sessions = yesterday.sessionCount
            let sessionLabel = sessions >= 3 ? L10n.s("label.deepSession") : L10n.s("label.session")
            if let project = yesterday.primaryProjectName {
                return L10n.tpl("body.dayWithProject", [
                    "turns": "<hi>\(turns)</hi>",
                    "sessions": "<hi>\(sessions)</hi>",
                    "sessionLabel": sessionLabel,
                    "project": project
                ])
            } else {
                return L10n.tpl("body.dayNoProject", [
                    "turns": "<hi>\(turns)</hi>",
                    "sessions": "<hi>\(sessions)</hi>",
                    "sessionLabel": sessionLabel
                ])
            }
        } else {
            let active = week.days.filter(\.hasActivity).count
            let peak = week.peakDay
            let peakName = peak.map { L10n.weekdayShort(for: $0.date) } ?? ""
            return L10n.tpl("body.week", [
                "activeDays": "<hi>\(active)</hi>",
                "weekday": peakName
            ])
        }
    }

    private func smartInsight(yesterday: DailyReport, week: WeeklyReport, lastWeek: WeeklyReport?) -> String? {
        let rec = PersonalRecords.check(day: yesterday)
        if rec.brokeTurns && yesterday.turnCount >= 50 {
            return L10n.tpl("insight.newRecordTurns", ["n": "<hi>\(yesterday.turnCount)</hi>"])
        }
        if rec.brokeFocus && yesterday.focusMinutes >= 120 {
            return L10n.s("insight.newRecordFocus")
        }
        let twoWeekMax = (week.days + (lastWeek?.days ?? []))
            .map { $0.longestFlowBlockMinutes }
            .max() ?? 0
        if yesterday.longestFlowBlockMinutes > 0 && yesterday.longestFlowBlockMinutes >= twoWeekMax {
            return L10n.s("insight.longestFlow")
        }
        if week.streak == 3 || week.streak == 7 || week.streak == 14 {
            return L10n.tpl("insight.streakMilestone", ["n": "<hi>\(week.streak)</hi>"])
        }
        return nil
    }

    // MARK: - Week rhythm

    @ViewBuilder
    private func weekRhythm(week: WeeklyReport) -> some View {
        let values = week.days.map(\.turnCount)
        let maxVal = max(1, values.max() ?? 1)
        let blocks = ["·", "▁", "▂", "▃", "▅", "▇", "█"]

        HStack(spacing: 0) {
            ForEach(Array(week.days.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 8) {
                    let ratio = Double(day.turnCount) / Double(maxVal)
                    let level: Int = {
                        if day.turnCount == 0 { return 0 }
                        let idx = Int((ratio * Double(blocks.count - 1)).rounded())
                        return max(1, min(blocks.count - 1, idx))
                    }()
                    Text(blocks[level])
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(day.turnCount > 0 ? Self.lime : Self.ink.opacity(0.15))
                    Text(L10n.weekdayShort(for: day.date))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Self.ink.opacity(0.45))
                    Text("\(day.turnCount)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Self.ink.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Highlights

    private func weekHighlightLines(week: WeeklyReport, lastWeek: WeeklyReport?) -> [String] {
        var lines: [String] = []
        if let peak = week.peakDay, peak.turnCount > 0 {
            lines.append(L10n.tpl("highlight.peakDay", [
                "weekday": L10n.weekdayShort(for: peak.date),
                "turns": "\(peak.turnCount)"
            ]))
        }
        if week.longestFlowBlockMinutes > 0, let date = week.peakBurstDate {
            lines.append(L10n.tpl("highlight.longestStretch", [
                "weekday": L10n.weekdayShort(for: date),
                "min": "\(week.longestFlowBlockMinutes)"
            ]))
        }
        if week.streak >= 3 {
            lines.append(L10n.tpl("highlight.streak", ["n": "\(week.streak)"]))
        }
        if let lw = lastWeek, lw.hasActivity {
            let diff = week.turnCount - lw.turnCount
            let pct = lw.turnCount > 0 ? Int((Double(abs(diff)) / Double(lw.turnCount) * 100).rounded()) : 0
            if pct >= 10 {
                if diff > 0 {
                    lines.append(L10n.tpl("highlight.vsLastWeek", ["pct": "\(pct)"]))
                } else {
                    lines.append(L10n.tpl("highlight.vsLastWeekDown", ["pct": "\(pct)"]))
                }
            }
        }
        if week.filesEdited > 0 {
            lines.append(L10n.tpl("highlight.files", ["n": "\(week.filesEdited)"]))
        }
        return lines
    }

    private func highlightList(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 10) {
                    Text("§")
                        .font(.system(size: 12, weight: .bold, design: .serif))
                        .foregroundColor(Self.lime.opacity(0.8))
                    Text(line)
                        .font(.system(size: 12, design: .serif))
                        .foregroundColor(Self.ink.opacity(0.78))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Breakdown columns (Tools / Skills / MCP)

    private struct Breakdown: Sendable {
        let title: String
        let items: [(String, Int)]
    }

    private func breakdownSections(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> [Breakdown] {
        let tools = isDay ? yesterday.toolCounts : week.toolCounts
        let skills = isDay ? yesterday.skillCounts : week.skillCounts
        let mcps = isDay ? yesterday.mcpServerCounts : week.mcpServerCounts
        var out: [Breakdown] = []
        let topTools = tools.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
        if !topTools.isEmpty {
            out.append(Breakdown(title: L10n.s("section.tools"), items: Array(topTools)))
        }
        let topSkills = skills.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
        if !topSkills.isEmpty {
            out.append(Breakdown(title: L10n.s("section.skills"), items: Array(topSkills)))
        }
        let topMcps = mcps.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
        if !topMcps.isEmpty {
            out.append(Breakdown(title: L10n.s("section.mcp"), items: Array(topMcps)))
        }
        return out
    }

    @ViewBuilder
    private func breakdownColumns(_ breakdowns: [Breakdown]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(breakdowns.enumerated()), id: \.offset) { i, bd in
                VStack(alignment: .leading, spacing: 6) {
                    Text(bd.title.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.6)
                        .foregroundColor(Self.ink.opacity(0.42))
                        .padding(.bottom, 4)
                    ForEach(Array(bd.items.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 4) {
                            Text(truncate(item.0, 11))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Self.ink.opacity(0.78))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text("\(item.1)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(Self.ink.opacity(0.55))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .topLeading)

                if i < breakdowns.count - 1 {
                    Rectangle()
                        .fill(Self.ink.opacity(0.12))
                        .frame(width: 0.5, height: 140)
                }
            }
        }
    }

    // MARK: - Editor's Note

    @ViewBuilder
    private func editorsNoteBox(for day: DailyReport) -> some View {
        if !notes.isEnabled && !notes.consentAsked {
            optInCard(for: day)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.isChinese ? "编辑寄语" : "FROM THE EDITOR")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.8)
                        .foregroundColor(Self.ink.opacity(0.42))
                    Spacer()
                    if notes.isEnabled {
                        Button {
                            if mode == .day {
                                notes.loadOrGenerateDay(for: day, force: true)
                            } else if let week = analytics.thisWeek {
                                notes.loadOrGenerateWeek(for: week, lastWeek: analytics.lastWeek, force: true)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Self.ink.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                }

                let scope: EditorsNoteService.Scope = mode == .day ? .day : .week
                switch notes.state(for: scope) {
                case .idle:
                    EmptyView()
                case .loading:
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.5)
                        Text(L10n.s("note.loading"))
                            .font(.system(size: 11, design: .serif))
                            .italic()
                            .foregroundColor(Self.ink.opacity(0.4))
                    }
                case .loaded(let note):
                    VStack(alignment: .leading, spacing: 10) {
                        Text(note.summary)
                            .font(.system(size: 13, weight: .regular, design: .serif))
                            .italic()
                            .foregroundColor(Self.ink.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(4)
                        if !note.tips.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(note.tips.enumerated()), id: \.offset) { _, tip in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("§")
                                            .font(.system(size: 12, weight: .bold, design: .serif))
                                            .foregroundColor(Self.lime.opacity(0.75))
                                        Text(tip)
                                            .font(.system(size: 12, design: .serif))
                                            .foregroundColor(Self.ink.opacity(0.7))
                                            .fixedSize(horizontal: false, vertical: true)
                                            .lineSpacing(4)
                                    }
                                }
                            }
                        }
                    }
                case .error:
                    Text(L10n.s("note.error"))
                        .font(.system(size: 11, design: .serif))
                        .italic()
                        .foregroundColor(Self.ink.opacity(0.3))
                }
            }
        }
    }

    @ViewBuilder
    private func optInCard(for day: DailyReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.s("note.consentBody"))
                .font(.system(size: 11, design: .serif))
                .italic()
                .foregroundColor(Self.ink.opacity(0.55))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    notes.setEnabled(true)
                    if mode == .day {
                        notes.loadOrGenerateDay(for: day)
                    } else if let week = analytics.thisWeek {
                        notes.loadOrGenerateWeek(for: week, lastWeek: analytics.lastWeek)
                    }
                } label: {
                    Text(L10n.s("note.consentEnable"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Self.lime))
                }
                .buttonStyle(.plain)
                Button {
                    notes.setEnabled(false)
                } label: {
                    Text(L10n.s("note.consentCancel"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Self.ink.opacity(0.55))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private static func humanMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        if m == 0 { return "\(h)h" }
        return "\(h)h\(m)m"
    }

    private static func formatMinutes(_ minutes: Int) -> String {
        humanMinutes(minutes)
    }
}
