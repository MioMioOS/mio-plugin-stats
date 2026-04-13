//
//  Localization.swift
//  StatsPlugin
//
//  Lightweight zh/en string map. Avoids the complexity of packaging
//  .lproj resources inside a .bundle plugin — at this plugin's size
//  a single lookup table is cleaner.
//

import Foundation

enum L10n {
    /// true if the user has set the app language to Chinese.
    /// Reads the same `appLanguage` UserDefaults key the host app uses,
    /// so an explicit zh/en choice in CodeIsland settings carries over here.
    /// Values: "zh" → Chinese, "en" → English, "auto" (or missing) → follow system.
    static var isChinese: Bool {
        let setting = UserDefaults.standard.string(forKey: "appLanguage") ?? "auto"
        switch setting {
        case "zh": return true
        case "en": return false
        default:
            // Fall back to system locale — check multiple sources for robustness.
            if let code = Locale.current.language.languageCode?.identifier,
               code.hasPrefix("zh") {
                return true
            }
            if let pref = Locale.preferredLanguages.first,
               pref.hasPrefix("zh") {
                return true
            }
            return false
        }
    }

    static func s(_ key: String) -> String {
        if isChinese { return zh[key] ?? key }
        return en[key] ?? key
    }

    // MARK: - Chinese

    private static let zh: [String: String] = [
        "mode.day": "昨天",
        "mode.week": "本周",

        "eyebrow.day": "昨天",
        "eyebrow.week": "本周",

        "hero.unit.day": "小时 专注",
        "hero.unit.week": "小时 专注",

        // Dynamic headlines
        "hl.deepDay": "一个深度专注的工作日",
        "hl.steady": "一个稳定的工作日",
        "hl.fragmented": "一个碎片化的日子",
        "hl.quiet": "一个安静的日子",
        "hl.multi": "一个多线程的工作日",
        "hl.night": "一个深夜的工作日",
        "hl.shipping": "一个全力交付的日子",
        "hl.exploring": "一个探索与思考的日子",
        "hl.debugging": "一个调试与排错的日子",
        "hl.record": "一个创纪录的日子",
        "hl.quietDay": "一个安静的日子",

        "hl.weekProductive": "一个高产的一周",
        "hl.weekSteady": "一个平稳的一周",
        "hl.weekUneven": "一个不均衡的一周",
        "hl.weekQuiet": "一个安静的一周",

        // Body sentences
        "body.dayWithProject": "{turns} 次互动 跨越 {sessions} 个{sessionLabel}，主要在 {project}",
        "body.dayNoProject": "{turns} 次互动 跨越 {sessions} 个{sessionLabel}",
        "body.week": "{activeDays} 天活跃，最忙的一天是{weekday}",
        "body.projectSplit": "分布在 {n} 个项目上",

        "label.session": "会话",
        "label.deepSession": "深度会话",

        // Ticker items
        "ticker.longest": "最长不间断 {n}m",
        "ticker.peakHour": "{hour}:00 高峰",
        "ticker.lines": "{n} 行代码",
        "ticker.streak": "连续活跃 {n} 天",
        "ticker.peakDay": "峰值日 {weekday}",
        "ticker.vsLastWeek": "较上周 {sign}{pct}%",
        "ticker.workWindow": "{from} 开始 → {to} 收工",
        "ticker.flowBlocks": "{n} 段心流",
        "ticker.firstLast": "{from} → {to}",

        // Additional editorial sections
        "section.tools": "常用工具",
        "section.skills": "技能调用",
        "section.mcp": "MCP 插件",
        "section.rhythm": "本周节律",
        "section.highlights": "本周高光",
        "section.projects": "项目分布",

        "highlight.peakDay": "{weekday} 最忙，共 {turns} 次互动",
        "highlight.longestStretch": "{weekday}最长不间断专注 {min}m",
        "highlight.streak": "连续活跃 {n} 天",
        "highlight.vsLastWeek": "比上周多 {pct}%",
        "highlight.vsLastWeekDown": "比上周少 {pct}%",
        "highlight.files": "编辑了 {n} 个文件",

        // Insight line (replaces body when detected)
        "insight.newRecordTurns": "今日 {n} 次互动创历史新高",
        "insight.newRecordFocus": "今日专注时长创历史新高",
        "insight.longestFlow": "近两周最长的一次不间断专注",
        "insight.backAfter": "时隔 {n} 天再次回到 {project}",
        "insight.heavyShip": "一个产出密集的日子",
        "insight.exploration": "一个探索与思考的日子",
        "insight.digging": "大量调试与搜索",
        "insight.streakMilestone": "连续活跃第 {n} 天",

        // Empty / loading
        "state.loading": "正在扫描活动数据",
        "state.empty": "暂无活动数据",
        "state.emptyHint": "启动一个 Claude Code 会话后再来看看",

        // Editor's note
        "note.title": "编辑寄语",
        "note.loading": "正在思考...",
        "note.consentTitle": "启用 AI 洞察？",
        "note.consentBody": "CodeIsland 会调用你本地的 claude 命令行，基于当天的聚合统计数字（不含任何源代码）生成一段简短的点评和改进建议。数据不经过任何第三方服务器。",
        "note.consentEnable": "启用",
        "note.consentCancel": "暂不启用",
        "note.error": "暂时无法生成洞察",
        "note.refresh": "重新生成",
        "note.disabled": "AI 洞察已关闭",

        // Weekdays (short)
        "wd.mon": "周一",
        "wd.tue": "周二",
        "wd.wed": "周三",
        "wd.thu": "周四",
        "wd.fri": "周五",
        "wd.sat": "周六",
        "wd.sun": "周日",

        // Months
        "month.short": "{m}月",
        "date.dayShort": "{m}月{d}日",
    ]

    // MARK: - English

    private static let en: [String: String] = [
        "mode.day": "Yesterday",
        "mode.week": "This Week",

        "eyebrow.day": "YESTERDAY",
        "eyebrow.week": "THIS WEEK",

        "hero.unit.day": "h focus",
        "hero.unit.week": "h focus",

        "hl.deepDay": "A deep day",
        "hl.steady": "A steady day",
        "hl.fragmented": "A scattered day",
        "hl.quiet": "A quiet day",
        "hl.multi": "A multi-track day",
        "hl.night": "A late-night push",
        "hl.shipping": "A shipping day",
        "hl.exploring": "A day of exploration",
        "hl.debugging": "A day of digging",
        "hl.record": "A record-breaking day",
        "hl.quietDay": "A quiet day",

        "hl.weekProductive": "A productive week",
        "hl.weekSteady": "A steady week",
        "hl.weekUneven": "An uneven week",
        "hl.weekQuiet": "A quiet week",

        "body.dayWithProject": "{turns} turns across {sessions} {sessionLabel}, mostly on {project}",
        "body.dayNoProject": "{turns} turns across {sessions} {sessionLabel}",
        "body.week": "Active on {activeDays} days, peak on {weekday}",
        "body.projectSplit": "spread across {n} projects",

        "label.session": "session",
        "label.deepSession": "deep session",

        "ticker.longest": "longest stretch {n}m",
        "ticker.peakHour": "peak at {hour}:00",
        "ticker.lines": "{n} lines written",
        "ticker.streak": "{n} day streak",
        "ticker.peakDay": "peak {weekday}",
        "ticker.vsLastWeek": "{sign}{pct}% vs last week",
        "ticker.workWindow": "{from} → {to}",
        "ticker.flowBlocks": "{n} flow blocks",
        "ticker.firstLast": "{from} → {to}",

        "section.tools": "MOST-USED TOOLS",
        "section.skills": "SKILLS",
        "section.mcp": "MCP",
        "section.rhythm": "WEEKLY RHYTHM",
        "section.highlights": "HIGHLIGHTS",
        "section.projects": "PROJECTS",

        "highlight.peakDay": "Peak on {weekday} with {turns} turns",
        "highlight.longestStretch": "Longest deep stretch {min}m on {weekday}",
        "highlight.streak": "{n}-day active streak",
        "highlight.vsLastWeek": "{pct}% more than last week",
        "highlight.vsLastWeekDown": "{pct}% less than last week",
        "highlight.files": "{n} files touched",

        "insight.newRecordTurns": "{n} active turns — a new personal best",
        "insight.newRecordFocus": "longest focus session of any day you've tracked",
        "insight.longestFlow": "your longest deep stretch in two weeks",
        "insight.backAfter": "Back on {project} after {n} quiet days",
        "insight.heavyShip": "A heavy shipping day",
        "insight.exploration": "A day of exploration and thinking",
        "insight.digging": "A day of debugging and search",
        "insight.streakMilestone": "{n}-day streak and counting",

        "state.loading": "Scanning activity data",
        "state.empty": "No activity yet",
        "state.emptyHint": "Start a Claude Code session and come back",

        "note.title": "Editor's Note",
        "note.loading": "Thinking...",
        "note.consentTitle": "Enable AI insights?",
        "note.consentBody": "CodeIsland will call your local claude CLI with today's aggregate stats (no source code, only numbers) to generate a short note and improvement suggestions. Nothing is sent to any third-party server.",
        "note.consentEnable": "Enable",
        "note.consentCancel": "Not now",
        "note.error": "Couldn't generate insights",
        "note.refresh": "Regenerate",
        "note.disabled": "AI insights disabled",

        "wd.mon": "Mon",
        "wd.tue": "Tue",
        "wd.wed": "Wed",
        "wd.thu": "Thu",
        "wd.fri": "Fri",
        "wd.sat": "Sat",
        "wd.sun": "Sun",

        "month.short": "{m}",
        "date.dayShort": "{m} {d}",
    ]

    // MARK: - Formatters

    static func tpl(_ key: String, _ vars: [String: String] = [:]) -> String {
        var str = s(key)
        for (k, v) in vars {
            str = str.replacingOccurrences(of: "{\(k)}", with: v)
        }
        return str
    }

    static func weekdayShort(for date: Date) -> String {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let keys = ["wd.sun", "wd.mon", "wd.tue", "wd.wed", "wd.thu", "wd.fri", "wd.sat"]
        return s(keys[weekday - 1])
    }

    static func dayDate(_ date: Date) -> String {
        let cal = Calendar.current
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        if isChinese {
            return "\(m)月\(d)日"
        } else {
            let monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
            return "\(monthNames[m - 1]) \(d)"
        }
    }

    static func weekRange(_ start: Date, _ end: Date) -> String {
        let cal = Calendar.current
        let sm = cal.component(.month, from: start)
        let sd = cal.component(.day, from: start)
        let em = cal.component(.month, from: end)
        let ed = cal.component(.day, from: end)
        if isChinese {
            if sm == em {
                return "\(sm)月\(sd)–\(ed)日"
            } else {
                return "\(sm)月\(sd)日 – \(em)月\(ed)日"
            }
        } else {
            let mn = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
            if sm == em {
                return "\(mn[sm - 1]) \(sd)–\(ed)"
            } else {
                return "\(mn[sm - 1]) \(sd) – \(mn[em - 1]) \(ed)"
            }
        }
    }

    static func clockTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
