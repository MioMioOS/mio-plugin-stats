//
//  AnalyticsCollector.swift
//  StatsPlugin
//
//  Scans ~/.claude/projects/*/*.jsonl and computes per-day activity reports
//  for the last 14 local days (7 for "this week" + 7 for "last week" used
//  as a comparison baseline). Runs once on app launch and then again at
//  each midnight. Results are cached in memory and published via Combine
//  so the notch menu's DailyReportCard can observe them.
//
//  Design notes:
//    - All JSONL files are read **once**. Each line is bucketized into the
//      local-day it belongs to. Much cheaper than scanning N days × M files.
//    - "Yesterday" is the most recent day we report. Today is in flight
//      and would be misleading.
//    - Skill invocations (tool name == "Skill") and MCP plugin calls
//      (tool name prefix "mcp__") are split into their own buckets from
//      the built-in tool counts, so the UI can show them separately.
//

import Foundation
import Combine
import os.log

// MARK: - File-level non-isolated helpers
//
// These types/values live OUTSIDE the @MainActor class so Swift doesn't
// infer MainActor isolation for them. The heavy scan runs off the main
// actor in a Task.detached + TaskGroup, and every helper it touches
// (logger, DayBucket, CachedAnalytics) must be reachable from that
// nonisolated context without cross-actor hops.

/// os.log handle for analytics. File-scope `let` so it's fully Sendable
/// and usable from any isolation domain.
private let analyticsLogger = Logger(subsystem: "com.codeisland", category: "Analytics")

/// On-disk snapshot of the last successful scan. Stored as JSON in
/// Application Support so a warm start can paint the card instantly
/// while a fresh scan runs in the background.
private struct CachedAnalytics: Codable, Sendable {
    let thisWeek: WeeklyReport
    let lastWeek: WeeklyReport
}

/// Per-day mutable accumulator used during the scan. Lives at file scope
/// (not nested in AnalyticsCollector) so it's free of MainActor isolation
/// and can be freely mutated from a background task. Marked
/// `@unchecked Sendable` because each instance is owned by exactly one
/// worker task at a time — the TaskGroup hands a fresh array of buckets
/// to each worker, then merges them serially on the main task.
private final class DayBucket: @unchecked Sendable {
    let dayStart: Date
    var sessionIds = Set<String>()
    var turnCount = 0
    var toolCounts: [String: Int] = [:]
    var skillCounts: [String: Int] = [:]
    var mcpServerCounts: [String: Int] = [:]
    var linesWritten = 0
    var projectTurns: [String: Int] = [:]
    var sessionTimestamps: [String: [Date]] = [:]
    // Per-session, per-timestamp project name (used to split focus into projects)
    var sessionTimestampProjects: [String: [(Date, String?)]] = [:]
    var filesEdited = Set<String>()
    var turnsByHour: [Int: Int] = [:]
    var firstActivity: Date?
    var lastActivity: Date?

    init(dayStart: Date) {
        self.dayStart = dayStart
    }

    /// Merge another bucket's accumulated state into self. Used by the
    /// parallel scanner: each worker fills its own bucket set, then the
    /// main task merges all of them into a master set.
    func merge(from other: DayBucket) {
        sessionIds.formUnion(other.sessionIds)
        turnCount += other.turnCount
        for (k, v) in other.toolCounts       { toolCounts[k, default: 0] += v }
        for (k, v) in other.skillCounts      { skillCounts[k, default: 0] += v }
        for (k, v) in other.mcpServerCounts  { mcpServerCounts[k, default: 0] += v }
        linesWritten += other.linesWritten
        for (k, v) in other.projectTurns     { projectTurns[k, default: 0] += v }
        for (k, v) in other.sessionTimestamps {
            sessionTimestamps[k, default: []].append(contentsOf: v)
        }
        for (k, v) in other.sessionTimestampProjects {
            sessionTimestampProjects[k, default: []].append(contentsOf: v)
        }
        filesEdited.formUnion(other.filesEdited)
        for (k, v) in other.turnsByHour      { turnsByHour[k, default: 0] += v }
        if let f = other.firstActivity, firstActivity == nil || f < firstActivity! {
            firstActivity = f
        }
        if let l = other.lastActivity, lastActivity == nil || l > lastActivity! {
            lastActivity = l
        }
    }

    /// Finalize this bucket into an immutable DailyReport. Computes focus
    /// minutes, peak burst, project time split, and flow blocks.
    func finalize() -> DailyReport {
        var focusSeconds: TimeInterval = 0
        var peakBurstSeconds: TimeInterval = 0
        let burstGap: TimeInterval = 5 * 60   // loose gap — for focus/peak burst
        let flowGap: TimeInterval = 2 * 60    // strict gap — for real flow blocks
        let flowThreshold: TimeInterval = 15 * 60

        // Per-project time accumulator
        var projectSeconds: [String: TimeInterval] = [:]
        var flowBlocks = 0
        var longestFlowSeconds: TimeInterval = 0

        for (sid, timestamps) in sessionTimestamps {
            let sorted = timestamps.sorted()
            guard let first = sorted.first else { continue }

            // Determine the dominant project for this session (best-effort).
            // We use the most-frequent project across this session's timestamps.
            let tsProjects = sessionTimestampProjects[sid] ?? []
            var projCounts: [String: Int] = [:]
            for (_, p) in tsProjects {
                if let p { projCounts[p, default: 0] += 1 }
            }
            let sessionProject = projCounts.max { $0.value < $1.value }?.key

            // LOOSE pass — focus minutes and peak burst (existing semantics)
            var burstStart = first
            var burstEnd = first
            for ts in sorted.dropFirst() {
                if ts.timeIntervalSince(burstEnd) <= burstGap {
                    burstEnd = ts
                } else {
                    let dur = burstEnd.timeIntervalSince(burstStart)
                    focusSeconds += dur
                    if dur > peakBurstSeconds { peakBurstSeconds = dur }
                    if let p = sessionProject { projectSeconds[p, default: 0] += dur }
                    burstStart = ts
                    burstEnd = ts
                }
            }
            let finalDur = burstEnd.timeIntervalSince(burstStart)
            focusSeconds += finalDur
            if finalDur > peakBurstSeconds { peakBurstSeconds = finalDur }
            if let p = sessionProject { projectSeconds[p, default: 0] += finalDur }

            // STRICT pass — flow blocks (2-min gap, ≥15 min duration)
            var fStart = first
            var fEnd = first
            for ts in sorted.dropFirst() {
                if ts.timeIntervalSince(fEnd) <= flowGap {
                    fEnd = ts
                } else {
                    let dur = fEnd.timeIntervalSince(fStart)
                    if dur >= flowThreshold {
                        flowBlocks += 1
                        if dur > longestFlowSeconds { longestFlowSeconds = dur }
                    }
                    fStart = ts
                    fEnd = ts
                }
            }
            let fDur = fEnd.timeIntervalSince(fStart)
            if fDur >= flowThreshold {
                flowBlocks += 1
                if fDur > longestFlowSeconds { longestFlowSeconds = fDur }
            }
        }

        let projectMinutes: [String: Int] = projectSeconds.mapValues { Int(($0 / 60).rounded()) }

        return DailyReport(
            date: dayStart,
            sessionCount: sessionIds.count,
            turnCount: turnCount,
            focusMinutes: Int((focusSeconds / 60).rounded()),
            toolCounts: toolCounts,
            skillCounts: skillCounts,
            mcpServerCounts: mcpServerCounts,
            linesWritten: linesWritten,
            primaryProjectName: projectTurns.max { $0.value < $1.value }?.key,
            projectCount: projectTurns.count,
            peakBurstMinutes: Int((peakBurstSeconds / 60).rounded()),
            filesEdited: filesEdited.count,
            peakHour: turnsByHour.max { $0.value < $1.value }?.key,
            firstActivity: firstActivity,
            lastActivity: lastActivity,
            flowBlockCount: flowBlocks,
            longestFlowBlockMinutes: Int((longestFlowSeconds / 60).rounded()),
            projectTimes: projectMinutes
        )
    }
}

@MainActor
final class AnalyticsCollector: ObservableObject {
    static let shared = AnalyticsCollector()

    /// The most recent full day's report (yesterday). Nil until first compute finishes.
    /// Kept as a shortcut for the old single-day consumers.
    @Published private(set) var yesterdayReport: DailyReport?
    /// 7 daily reports ending yesterday, chronological (oldest → newest).
    /// `last` == yesterday. Empty until first compute finishes.
    @Published private(set) var thisWeek: WeeklyReport?
    /// 7 daily reports for the week before that — used purely as a comparison
    /// baseline for "vs last week".
    @Published private(set) var lastWeek: WeeklyReport?
    /// True while a compute is in progress, so the UI can show a spinner.
    @Published private(set) var isComputing: Bool = false
    /// True once the very first scan has completed (even if it found nothing).
    /// DailyReportCard uses this to decide whether to show a loading animation
    /// or the actual card. False at launch, true forever after the first scan.
    @Published private(set) var hasLoadedOnce: Bool = false

    private var midnightTimer: Timer?

    private init() {}

    // MARK: - Public API

    /// Call once on app launch. Loads any persisted cache (so the card
    /// appears instantly on warm starts), then kicks off a fresh compute
    /// in the background, then schedules the next compute at local-midnight.
    func start() {
        // 1. Try to hydrate from the on-disk cache first. If it exists AND
        //    is for yesterday's date, we can show the card instantly and
        //    skip the scan entirely on warm starts.
        if let cached = Self.loadCache() {
            self.thisWeek = cached.thisWeek
            self.lastWeek = cached.lastWeek
            self.yesterdayReport = cached.thisWeek.days.last
            self.hasLoadedOnce = true
            analyticsLogger.info("Loaded analytics cache: 7d turns=\(cached.thisWeek.turnCount)")
        }
        // 2. Always fire a background recompute — even if the cache was
        //    fresh, the user might have worked more since. On warm starts
        //    with a valid cache, recomputeIfNeeded() will no-op early
        //    because thisWeek.days.last matches yesterday.
        Task { await recomputeIfNeeded() }
        scheduleNextMidnight()
    }

    /// Force a recompute. Used by the midnight timer and manually on launch.
    ///
    /// IMPORTANT: the heavy scan runs OFF the main actor via the nonisolated
    /// `computeTwoWeeks` static function. This is the whole reason first-launch
    /// feels instant now — the JSONL crawl no longer blocks the UI thread
    /// while we read+decode several hundred MB of data.
    func recomputeIfNeeded() async {
        isComputing = true
        defer { isComputing = false }

        let yesterdayStart = Self.yesterdayStart()
        // Skip if we already have a report dated the same day as yesterday.
        if let current = thisWeek?.days.last,
           Calendar.current.isDate(current.date, inSameDayAs: yesterdayStart) {
            hasLoadedOnce = true
            return
        }

        let started = Date()
        // Must use Task.detached to actually hop OFF the main actor.
        // `nonisolated` alone is not enough: Swift will happily continue
        // executing a nonisolated async function on the caller's executor
        // (here: MainActor) unless we explicitly detach. Without this, the
        // 32-second JSONL crawl still runs on main and freezes the UI.
        let (thisWeek, lastWeek) = await Task.detached(priority: .utility) {
            () -> (WeeklyReport, WeeklyReport) in
            await Self.computeTwoWeeks(endingYesterday: yesterdayStart)
        }.value
        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        self.thisWeek = thisWeek
        self.lastWeek = lastWeek
        self.yesterdayReport = thisWeek.days.last
        self.hasLoadedOnce = true
        analyticsLogger.info("Weekly recompute done in \(elapsedMs)ms: 7d turns=\(thisWeek.turnCount) focusMin=\(thisWeek.focusMinutes) streak=\(thisWeek.streak) prevWeekTurns=\(lastWeek.turnCount)")
        // Persist the fresh result so the next launch is instant.
        Self.saveCache(CachedAnalytics(thisWeek: thisWeek, lastWeek: lastWeek))
    }

    // MARK: - Persistence

    /// Path to the cache file. Creates the parent directory on first use.
    nonisolated private static func cacheFileURL() -> URL? {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = appSupport.appendingPathComponent("CodeIsland", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("analytics_cache.json")
    }

    /// Try to read the cached report from disk. Returns nil on any error —
    /// missing file, corrupt JSON, model shape drift etc. All non-fatal:
    /// the worst case is we fall back to a fresh scan.
    nonisolated private static func loadCache() -> CachedAnalytics? {
        guard let url = cacheFileURL(),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedAnalytics.self, from: data)
    }

    /// Write the cache to disk. Called after every successful scan. Errors
    /// are logged but swallowed — cache persistence is a best-effort
    /// optimization, not a correctness requirement.
    nonisolated private static func saveCache(_ cached: CachedAnalytics) {
        guard let url = cacheFileURL() else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(cached)
            try data.write(to: url, options: .atomic)
        } catch {
            analyticsLogger.warning("Failed to save analytics cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Scheduling

    private func scheduleNextMidnight() {
        midnightTimer?.invalidate()
        let nextMidnight = Self.nextLocalMidnight()
        let interval = nextMidnight.timeIntervalSinceNow
        analyticsLogger.info("Next recompute scheduled in \(Int(interval))s at \(nextMidnight.description)")
        midnightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.recomputeIfNeeded()
                self?.scheduleNextMidnight()
            }
        }
    }

    // MARK: - Date helpers

    /// The start of yesterday in local time.
    static func yesterdayStart() -> Date {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        return cal.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
    }

    /// The next local midnight after now.
    static func nextLocalMidnight() -> Date {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        return cal.date(byAdding: .day, value: 1, to: todayStart) ?? Date().addingTimeInterval(86400)
    }

    // MARK: - Bucketed scanning

    /// Walk every JSONL file under ~/.claude/projects/* **once**, dropping
    /// each entry into the right day-bucket. Returns two WeeklyReports:
    /// (thisWeek, lastWeek), each a 7-day window ending yesterday.
    ///
    /// `nonisolated` so it can be awaited from the @MainActor context
    /// without dragging the scan onto the main thread.
    nonisolated private static func computeTwoWeeks(endingYesterday yesterdayStart: Date) async -> (WeeklyReport, WeeklyReport) {
        let cal = Calendar.current
        let projectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        // Build 14 day buckets: index 0 = oldest (13 days ago), index 13 = yesterday.
        // lastWeek = indices 0..<7, thisWeek = indices 7..<14.
        var buckets: [DayBucket] = []
        for offset in (0..<14).reversed() {
            let dayStart = cal.date(byAdding: .day, value: -offset, to: yesterdayStart) ?? yesterdayStart
            buckets.append(DayBucket(dayStart: dayStart))
        }
        let windowStart = buckets.first!.dayStart
        let windowEnd = yesterdayStart.addingTimeInterval(86400)

        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            analyticsLogger.warning("Could not enumerate \(projectsDir.path)")
            let emptyDays = buckets.map { $0.finalize() }
            return (
                WeeklyReport.aggregate(Array(emptyDays.suffix(7))),
                WeeklyReport.aggregate(Array(emptyDays.prefix(7)))
            )
        }

        // Drain the NSEnumerator into an array manually. `for case let x in
        // enumerator` is an NSFastEnumeration iterator, which Swift 6
        // bans inside async contexts because the underlying protocol
        // isn't Sendable. `nextObject()` in a while-loop sidesteps that
        // without changing behavior.
        var urls: [URL] = []
        while let obj = enumerator.nextObject() {
            guard let url = obj as? URL, url.pathExtension == "jsonl" else { continue }
            if let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               mtime < windowStart {
                continue
            }
            urls.append(url)
        }

        // PARALLEL SCAN:
        //   Split `urls` into `workerCount` chunks. Each worker owns its
        //   own set of 14 local DayBuckets (no shared mutable state), scans
        //   its chunk sequentially, and returns the buckets. The main task
        //   then merges all worker buckets into the master `buckets` array.
        //
        //   On a 10-core Apple Silicon machine this drops a 32s serial scan
        //   to roughly 8–10s. The merge step is cheap — just dict/set unions.
        let workerCount = 6
        let chunkSize = Swift.max(1, (urls.count + workerCount - 1) / workerCount)
        let chunks: [[URL]] = stride(from: 0, to: urls.count, by: chunkSize).map {
            Array(urls[$0..<Swift.min($0 + chunkSize, urls.count)])
        }

        await withTaskGroup(of: [DayBucket].self) { group in
            for chunk in chunks {
                group.addTask {
                    // Each worker gets its own 14-bucket array. Same day
                    // dates as the master so merging is index-to-index.
                    var localBuckets: [DayBucket] = []
                    for offset in (0..<14).reversed() {
                        let dayStart = cal.date(byAdding: .day, value: -offset, to: yesterdayStart) ?? yesterdayStart
                        localBuckets.append(DayBucket(dayStart: dayStart))
                    }
                    for url in chunk {
                        processJSONLFile(
                            url: url,
                            windowStart: windowStart,
                            windowEnd: windowEnd,
                            buckets: localBuckets,
                            calendar: cal
                        )
                    }
                    return localBuckets
                }
            }
            for await workerBuckets in group {
                for (i, wb) in workerBuckets.enumerated() where i < buckets.count {
                    buckets[i].merge(from: wb)
                }
            }
        }

        let days = buckets.map { $0.finalize() }
        let thisWeekDays = Array(days.suffix(7))
        let lastWeekDays = Array(days.prefix(7))
        return (
            WeeklyReport.aggregate(thisWeekDays),
            WeeklyReport.aggregate(lastWeekDays)
        )
    }

    /// Stream one JSONL file line-by-line, decoding each line and dropping
    /// the relevant fields into whichever day-bucket the timestamp falls in.
    nonisolated private static func processJSONLFile(
        url: URL,
        windowStart: Date,
        windowEnd: Date,
        buckets: [DayBucket],
        calendar: Calendar
    ) {
        guard let data = try? Data(contentsOf: url) else { return }
        let lines = data.split(separator: 0x0A)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]

        for lineData in lines {
            guard !lineData.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: Data(lineData)) as? [String: Any]
            else { continue }

            guard let tsString = obj["timestamp"] as? String else { continue }
            let ts: Date
            if let parsed = iso.date(from: tsString) {
                ts = parsed
            } else if let parsed = isoNoFrac.date(from: tsString) {
                ts = parsed
            } else {
                continue
            }
            guard ts >= windowStart, ts < windowEnd else { continue }

            // Figure out which bucket this line belongs to. Buckets are indexed
            // from windowStart; each one is exactly 86400s wide in local time.
            let daysSinceStart = calendar.dateComponents([.day], from: windowStart, to: ts).day ?? 0
            guard daysSinceStart >= 0, daysSinceStart < buckets.count else { continue }
            let bucket = buckets[daysSinceStart]

            guard let sessionId = obj["sessionId"] as? String else { continue }
            bucket.sessionIds.insert(sessionId)
            bucket.sessionTimestamps[sessionId, default: []].append(ts)

            // Track first/last activity for the day
            if bucket.firstActivity == nil || ts < bucket.firstActivity! {
                bucket.firstActivity = ts
            }
            if bucket.lastActivity == nil || ts > bucket.lastActivity! {
                bucket.lastActivity = ts
            }

            var projectName: String? = nil
            if let cwd = obj["cwd"] as? String {
                let name = URL(fileURLWithPath: cwd).lastPathComponent
                if !name.isEmpty {
                    bucket.projectTurns[name, default: 0] += 1
                    projectName = name
                }
            }
            bucket.sessionTimestampProjects[sessionId, default: []].append((ts, projectName))

            let type = obj["type"] as? String
            if type == "user" {
                if isRealUserTurn(obj) {
                    bucket.turnCount += 1
                    let hour = calendar.component(.hour, from: ts)
                    bucket.turnsByHour[hour, default: 0] += 1
                }
            } else if type == "assistant" {
                guard let message = obj["message"] as? [String: Any],
                      let contentBlocks = message["content"] as? [[String: Any]]
                else { continue }
                for block in contentBlocks {
                    guard let blockType = block["type"] as? String,
                          blockType == "tool_use",
                          let name = block["name"] as? String
                    else { continue }
                    let input = block["input"] as? [String: Any] ?? [:]

                    // Route the call to the right bucket: MCP, Skill, or built-in.
                    if name.hasPrefix("mcp__") {
                        // Format: mcp__<server>__<tool_name>
                        let server = mcpServerName(from: name)
                        bucket.mcpServerCounts[server, default: 0] += 1
                    } else if name == "Skill" {
                        // Slash-commands and skill invocations carry the actual
                        // name as `input.skill`. Anonymous/malformed calls are
                        // grouped under "Skill" as a fallback.
                        let skillName = (input["skill"] as? String) ?? "Skill"
                        bucket.skillCounts[skillName, default: 0] += 1
                    } else {
                        bucket.toolCounts[name, default: 0] += 1
                    }

                    bucket.linesWritten += linesForTool(name: name, input: input)
                    if let filePath = input["file_path"] as? String, !filePath.isEmpty {
                        bucket.filesEdited.insert(filePath)
                    }
                }
            }
        }
    }

    /// Extract the server segment from an `mcp__<server>__<tool>` tool name.
    /// Falls back to the full name if the shape is unexpected.
    nonisolated private static func mcpServerName(from toolName: String) -> String {
        // Strip leading "mcp__"
        let rest = String(toolName.dropFirst("mcp__".count))
        // Find the next "__" separator
        if let range = rest.range(of: "__") {
            return String(rest[rest.startIndex..<range.lowerBound])
        }
        return rest.isEmpty ? toolName : rest
    }

    /// True if this "user"-typed entry represents an actual human prompt and
    /// not a synthetic tool-result echo.
    nonisolated private static func isRealUserTurn(_ obj: [String: Any]) -> Bool {
        guard let message = obj["message"] as? [String: Any] else { return false }
        if message["content"] is String { return true }
        if let blocks = message["content"] as? [[String: Any]] {
            for block in blocks {
                if (block["type"] as? String) == "tool_result" {
                    return false
                }
            }
            return !blocks.isEmpty
        }
        return false
    }

    /// Count lines contributed by one file-mutation tool invocation.
    nonisolated private static func linesForTool(name: String, input: [String: Any]) -> Int {
        switch name {
        case "Write":
            let content = input["content"] as? String ?? ""
            return content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        case "Edit":
            let newString = input["new_string"] as? String ?? ""
            return newString.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        case "MultiEdit":
            guard let edits = input["edits"] as? [[String: Any]] else { return 0 }
            return edits.reduce(0) { acc, edit in
                let newString = edit["new_string"] as? String ?? ""
                return acc + newString.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
            }
        default:
            return 0
        }
    }
}
