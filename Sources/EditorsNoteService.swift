//
//  EditorsNoteService.swift
//  StatsPlugin
//
//  Invokes the user's local `claude` CLI in non-interactive mode with
//  aggregate stats data to generate a short editorial note and one or
//  two improvement suggestions. Results are cached per-day in
//  UserDefaults so we don't burn Claude credits on every view.
//
//  Privacy: we only pass aggregate numbers (turns, focus minutes,
//  tool counts, project names). No source code, no file contents,
//  no user identity. The call runs entirely on the user's machine
//  under their own Claude account.
//

import Foundation

struct EditorsNote: Codable, Sendable {
    let summary: String
    let tips: [String]
}

@MainActor
final class EditorsNoteService: ObservableObject {
    static let shared = EditorsNoteService()

    enum State {
        case idle
        case loading
        case loaded(EditorsNote)
        case error(String)
    }

    enum Scope: String {
        case day
        case week
    }

    /// Per-mode state so switching day<->week doesn't blank out the
    /// other mode's note.
    @Published private(set) var dayState: State = .idle
    @Published private(set) var weekState: State = .idle

    func state(for scope: Scope) -> State {
        scope == .day ? dayState : weekState
    }

    private var didOfferThisSession = false

    private let udKeyEnabled = "stats.editorsNote.enabled"
    private let udKeyConsent = "stats.editorsNote.consentAsked"
    private let udKeyCachePrefix = "stats.editorsNote.cache."

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: udKeyEnabled)
    }

    var consentAsked: Bool {
        UserDefaults.standard.bool(forKey: udKeyConsent)
    }

    /// Returns true at most once per launch, and only if the user hasn't
    /// already answered the consent prompt in a previous session.
    func shouldOfferConsentOnce() -> Bool {
        if didOfferThisSession { return false }
        if consentAsked { return false }
        didOfferThisSession = true
        return true
    }

    func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: udKeyEnabled)
        UserDefaults.standard.set(true, forKey: udKeyConsent)
        UserDefaults.standard.synchronize()
        didOfferThisSession = true
        if !value {
            dayState = .idle
            weekState = .idle
        }
    }

    private func setState(_ value: State, scope: Scope) {
        if scope == .day { dayState = value }
        else { weekState = value }
    }

    /// Generate an editorial note for a single day. Used in day mode.
    func loadOrGenerateDay(for day: DailyReport, force: Bool = false) {
        guard isEnabled else { setState(.idle, scope: .day); return }
        let lang = L10n.isChinese ? "zh" : "en"
        let cacheKey = "\(udKeyCachePrefix)day.\(dateKey(day.date)).\(lang)"
        if !force, let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(EditorsNote.self, from: data) {
            setState(.loaded(cached), scope: .day)
            return
        }
        setState(.loading, scope: .day)
        let prompt = buildDayPrompt(day: day)
        Task {
            do {
                let note = try await runClaude(prompt: prompt)
                if let encoded = try? JSONEncoder().encode(note) {
                    UserDefaults.standard.set(encoded, forKey: cacheKey)
                }
                setState(.loaded(note), scope: .day)
            } catch {
                setState(.error(error.localizedDescription), scope: .day)
            }
        }
    }

    /// Generate an editorial note for the full week. Focuses on trends,
    /// streaks, rhythm and week-over-week comparison.
    func loadOrGenerateWeek(for week: WeeklyReport, lastWeek: WeeklyReport?, force: Bool = false) {
        guard isEnabled else { setState(.idle, scope: .week); return }
        let lang = L10n.isChinese ? "zh" : "en"
        // Cache by the last day of the week (i.e. yesterday) to roll over daily.
        let anchor = week.days.last?.date ?? Date()
        let cacheKey = "\(udKeyCachePrefix)week.\(dateKey(anchor)).\(lang)"
        if !force, let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(EditorsNote.self, from: data) {
            setState(.loaded(cached), scope: .week)
            return
        }
        setState(.loading, scope: .week)
        let prompt = buildWeekPrompt(week: week, lastWeek: lastWeek)
        Task {
            do {
                let note = try await runClaude(prompt: prompt)
                if let encoded = try? JSONEncoder().encode(note) {
                    UserDefaults.standard.set(encoded, forKey: cacheKey)
                }
                setState(.loaded(note), scope: .week)
            } catch {
                setState(.error(error.localizedDescription), scope: .week)
            }
        }
    }

    /// Backward-compatibility shim — default behavior is day-scope.
    func loadOrGenerate(for day: DailyReport, projectTimes: [String: Int], force: Bool = false) {
        loadOrGenerateDay(for: day, force: force)
    }

    // MARK: - Prompt

    // MARK: - Week prompt

    private func buildWeekPrompt(week: WeeklyReport, lastWeek: WeeklyReport?) -> String {
        let isZh = L10n.isChinese
        let langInstruction = isZh
            ? "IMPORTANT: respond entirely in Simplified Chinese (简体中文). Do not use English words except for proper nouns like file names or tool names."
            : "IMPORTANT: respond entirely in natural English. Keep the tone precise and editorial, not marketing-y."

        var lines: [String] = []
        let active = week.days.filter(\.hasActivity).count
        lines.append("- active days: \(active) / 7")
        lines.append("- total turns: \(week.turnCount)")
        lines.append("- total focus: \(week.focusMinutes) minutes")
        lines.append("- total flow blocks (≥15m deep work): \(week.flowBlockCount)")
        lines.append("- longest deep stretch: \(week.longestFlowBlockMinutes)m")
        lines.append("- streak ending yesterday: \(week.streak) days")
        lines.append("- total lines written: \(week.linesWritten)")
        lines.append("- total files touched: \(week.filesEdited)")
        lines.append("- distinct projects: \(week.projectCount)")
        if let primary = week.primaryProjectName {
            lines.append("- primary project: \(primary)")
        }
        if let peak = week.peakDay {
            let wd = L10n.weekdayShort(for: peak.date)
            lines.append("- peak day: \(wd) (\(peak.turnCount) turns, \(peak.focusMinutes)m focus)")
        }
        // Daily rhythm row
        let dailyTurns = week.days.map { day -> String in
            let wd = L10n.weekdayShort(for: day.date)
            return "\(wd)=\(day.turnCount)"
        }.joined(separator: " ")
        lines.append("- daily turns: \(dailyTurns)")

        // Project time distribution
        if !week.projectTimes.isEmpty {
            let pt = week.projectTimes.sorted { $0.value > $1.value }.prefix(4)
                .map { "\($0.key) \($0.value)m" }
                .joined(separator: ", ")
            lines.append("- project time: \(pt)")
        }

        let topTools = week.toolCounts.sorted { $0.value > $1.value }.prefix(5)
        if !topTools.isEmpty {
            lines.append("- top tools: \(topTools.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
        }
        let topSkills = week.skillCounts.sorted { $0.value > $1.value }.prefix(4)
        if !topSkills.isEmpty {
            lines.append("- top skills: \(topSkills.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
        }
        let topMcps = week.mcpServerCounts.sorted { $0.value > $1.value }.prefix(3)
        if !topMcps.isEmpty {
            lines.append("- top MCP: \(topMcps.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
        }

        // vs last week
        if let lw = lastWeek, lw.hasActivity {
            lines.append("- last week comparison:")
            lines.append("    - turns: \(lw.turnCount) (this week: \(week.turnCount))")
            lines.append("    - focus: \(lw.focusMinutes)m (this week: \(week.focusMinutes)m)")
            lines.append("    - active days: \(lw.days.filter(\.hasActivity).count)")
        }
        let stats = lines.joined(separator: "\n")

        return """
        You are a thoughtful engineering coach reviewing a full week of a developer's coding activity.
        Look at trends, rhythm, consistency across days, and any week-over-week movement.
        Do NOT focus on a single day — this is a weekly recap.

        Write a short editorial-style note (1-2 sentences, direct, no fluff, no marketing voice) about
        the SHAPE of the week (is it steady, uneven, front-loaded, back-loaded, fragmented, deep?)
        plus 1 to 2 concrete improvement suggestions targeting weekly patterns (not isolated incidents).

        Do not use emojis. Do not praise for the sake of praise. Be specific. Reference concrete
        numbers from the data when relevant.

        \(langInstruction)

        Weekly data:
        \(stats)

        Return ONLY valid JSON in this exact shape, no prose around it:
        {"summary": "...", "tips": ["...", "..."]}
        """
    }

    // MARK: - Day prompt

    private func buildDayPrompt(day: DailyReport) -> String {
        let projectTimes = day.projectTimes
        return buildPrompt(day: day, projectTimes: projectTimes)
    }

    private func buildPrompt(day: DailyReport, projectTimes: [String: Int]) -> String {
        let isZh = L10n.isChinese
        let langInstruction = isZh
            ? "IMPORTANT: respond entirely in Simplified Chinese (简体中文). Do not use any English words in the summary or tips unless they are proper nouns like file names or tool names."
            : "IMPORTANT: respond entirely in natural English. Keep the tone precise and editorial, not marketing-y."
        var lines: [String] = []
        lines.append("- turns: \(day.turnCount)")
        lines.append("- focus minutes: \(day.focusMinutes)")
        lines.append("- longest unbroken stretch: \(day.longestFlowBlockMinutes)m")
        lines.append("- flow blocks (≥15m deep work): \(day.flowBlockCount)")
        lines.append("- lines written: \(day.linesWritten)")
        lines.append("- files edited: \(day.filesEdited)")
        if !projectTimes.isEmpty {
            let pt = projectTimes.sorted { $0.value > $1.value }
                .map { "\($0.key) (\($0.value)m)" }
                .joined(separator: ", ")
            lines.append("- projects: \(pt)")
        }
        if let first = day.firstActivity, let last = day.lastActivity {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            lines.append("- work window: \(f.string(from: first)) to \(f.string(from: last))")
        }
        let topTools = day.toolCounts.sorted { $0.value > $1.value }.prefix(5)
        if !topTools.isEmpty {
            lines.append("- top tools: \(topTools.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
        }
        let topMcps = day.mcpServerCounts.sorted { $0.value > $1.value }.prefix(3)
        if !topMcps.isEmpty {
            lines.append("- top MCP: \(topMcps.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
        }
        let stats = lines.joined(separator: "\n")

        return """
        You are a thoughtful engineering coach reviewing one day of a developer's coding activity.
        Write a short editorial-style note (1-2 sentences, direct, no fluff, no marketing voice)
        plus 1 to 2 concrete improvement suggestions based on actual patterns in the data.

        Do not use emojis. Do not praise for the sake of praise. Be specific.

        \(langInstruction)

        Data:
        \(stats)

        Return ONLY valid JSON in this exact shape, no prose around it:
        {"summary": "...", "tips": ["...", "..."]}
        """
    }

    // MARK: - Subprocess

    private func runClaude(prompt: String) async throws -> EditorsNote {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let note = try Self.invokeClaudeBlocking(prompt: prompt)
                    continuation.resume(returning: note)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func invokeClaudeBlocking(prompt: String) throws -> EditorsNote {
        // Find claude in common locations
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.claude/local/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
        ]
        guard let claudePath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw NSError(domain: "EditorsNoteService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "claude CLI not found"
            ])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["-p", prompt, "--output-format", "text"]

        // Inherit PATH so sub-tools claude might spawn can find things
        var env = ProcessInfo.processInfo.environment
        let homeBin = "/opt/homebrew/bin:/usr/local/bin"
        if let path = env["PATH"] {
            env["PATH"] = "\(homeBin):\(path)"
        } else {
            env["PATH"] = homeBin
        }

        // Honor CodeIsland's "Anthropic API Proxy" user preference
        // (Settings → General). This plugin is loaded as a dylib into the
        // CodeIsland process so UserDefaults.standard resolves to the host
        // app's preferences. We inject HTTPS_PROXY / HTTP_PROXY / ALL_PROXY
        // into THIS subprocess's environment only — we do not call
        // launchctl setenv, so we do not pollute the global env used by
        // other GUI apps. Claude CLI itself already does the same thing
        // via a shell function wrapper (~/.claude/shell-snapshots/...),
        // this just mirrors that behavior for programmatic invocations.
        if let proxy = UserDefaults.standard.string(forKey: "anthropicProxyURL") {
            let trimmed = proxy.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                env["HTTPS_PROXY"] = trimmed
                env["HTTP_PROXY"] = trimmed
                env["ALL_PROXY"] = trimmed
                env["https_proxy"] = trimmed
                env["http_proxy"] = trimmed
                env["all_proxy"] = trimmed
            }
        }

        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Timeout: 45 seconds
        let deadline = Date().addingTimeInterval(45)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning {
                process.interrupt()
            }
            throw NSError(domain: "EditorsNoteService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "claude timeout"
            ])
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let err = String(data: stderrData, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "EditorsNoteService", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "claude exited \(process.terminationStatus): \(err.prefix(200))"
            ])
        }

        guard let raw = String(data: stdoutData, encoding: .utf8) else {
            throw NSError(domain: "EditorsNoteService", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "no output"
            ])
        }

        // Extract JSON — Claude sometimes wraps it in prose or code fences
        let json = extractJSON(from: raw)
        guard let jsonData = json.data(using: .utf8),
              let note = try? JSONDecoder().decode(EditorsNote.self, from: jsonData) else {
            throw NSError(domain: "EditorsNoteService", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "couldn't parse response"
            ])
        }
        return note
    }

    nonisolated private static func extractJSON(from text: String) -> String {
        // Strip markdown code fences
        var t = text
        if let fenceStart = t.range(of: "```json"), let fenceEnd = t.range(of: "```", range: fenceStart.upperBound..<t.endIndex) {
            t = String(t[fenceStart.upperBound..<fenceEnd.lowerBound])
        } else if let fenceStart = t.range(of: "```"), let fenceEnd = t.range(of: "```", range: fenceStart.upperBound..<t.endIndex) {
            t = String(t[fenceStart.upperBound..<fenceEnd.lowerBound])
        }
        // Trim to first { and last }
        if let firstBrace = t.firstIndex(of: "{"), let lastBrace = t.lastIndex(of: "}") {
            return String(t[firstBrace...lastBrace])
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dateKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
