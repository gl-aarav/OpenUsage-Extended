import Foundation

struct OpenCodeGoUsageSnapshot: Sendable {
    let rollingUsagePercent: Double
    let weeklyUsagePercent: Double
    let monthlyUsagePercent: Double
    let rollingResetInSec: Int
    let weeklyResetInSec: Int
    let monthlyResetInSec: Int
    let updatedAt: Date
}

enum OpenCodeGoUsageError: Error, LocalizedError, Equatable {
    case historyUnavailable(String)
    case sqliteFailed(String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .historyUnavailable(let detail):
            return "OpenCode Go usage history unavailable: \(detail)."
        case .sqliteFailed(let detail):
            return "OpenCode Go database read failed: \(detail)."
        case .parseFailed(let detail):
            return "OpenCode Go usage parse failed: \(detail)."
        }
    }
}

/// Reads local usage from the OpenCode Go SQLite database and converts it into rolling (5-hour),
/// weekly, and monthly percentage windows. Adapted from CodexBar (MIT licensed).
struct OpenCodeGoUsageReader: Sendable {
    private static let fiveHours: TimeInterval = 5 * 60 * 60
    private static let week: TimeInterval = 7 * 24 * 60 * 60
    private static let limits = (session: 12.0, weekly: 30.0, monthly: 60.0)

    private let databaseURL: URL
    private let processRunner: ProcessRunning

    init(
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/opencode.db", isDirectory: false),
        processRunner: ProcessRunning = SystemProcessRunner()
    ) {
        self.databaseURL = databaseURL
        self.processRunner = processRunner
    }

    func fetch(now: Date = Date()) throws -> OpenCodeGoUsageSnapshot {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw OpenCodeGoUsageError.historyUnavailable("database not found")
        }

        let rows = try readRows()
        guard !rows.isEmpty else {
            throw OpenCodeGoUsageError.historyUnavailable("no local usage rows")
        }
        return Self.snapshot(rows: rows, now: now)
    }

    // MARK: - SQLite query

    private struct UsageRow {
        let createdMs: Int64
        let cost: Double
    }

    private func readRows() throws -> [UsageRow] {
        let hasPartTable = try self.hasTable(named: "part")
        let sql = hasPartTable ? Self.messageAndPartUsageSQL : Self.messageUsageSQL

        let result = try processRunner.run(
            executable: "/usr/bin/sqlite3",
            arguments: [
                "-batch", "-noheader",
                "-cmd", ".mode json",
                "-cmd", ".timeout 1000",
                databaseURL.path,
                sql
            ],
            environment: [:],
            timeout: 5
        )
        guard result.succeeded else {
            throw OpenCodeGoUsageError.sqliteFailed(result.stderr)
        }

        let json = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            throw OpenCodeGoUsageError.parseFailed("invalid JSON output")
        }

        return array.compactMap { row in
            guard let createdMs = row["createdMs"] as? Int64,
                  let cost = row["cost"] as? Double else { return nil }
            return UsageRow(createdMs: createdMs, cost: cost)
        }
    }

    private func hasTable(named name: String) throws -> Bool {
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name='\(name)'"
        let result = try processRunner.run(
            executable: "/usr/bin/sqlite3",
            arguments: [
                "-batch", "-noheader",
                databaseURL.path,
                sql
            ],
            environment: [:],
            timeout: 5
        )
        return result.succeeded && !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static let messageUsageSQL = """
        SELECT
          CAST(time_created AS INTEGER) AS createdMs,
          CAST(COALESCE(json_extract(data, '$.cost'), 0) AS REAL) AS cost
        FROM message
        WHERE json_valid(data)
          AND json_extract(data, '$.providerID') IN ('opencode', 'opencode-go')
          AND json_extract(data, '$.role') = 'assistant'
          AND json_type(data, '$.cost') IN ('integer', 'real')
    """

    private static let messageAndPartUsageSQL = """
        WITH message_costs AS (
          SELECT
            time_created AS messageID,
            CAST(time_created AS INTEGER) AS createdMs,
            CAST(COALESCE(json_extract(data, '$.cost'), 0) AS REAL) AS cost
          FROM message
          WHERE json_valid(data)
            AND json_extract(data, '$.providerID') IN ('opencode', 'opencode-go')
            AND json_extract(data, '$.role') = 'assistant'
            AND json_type(data, '$.cost') IN ('integer', 'real')
        )
        SELECT createdMs, cost
        FROM message_costs
        UNION ALL
        SELECT
          CAST(COALESCE(json_extract(p.data, '$.time.created'), p.time_created, m.time_created) AS INTEGER)
            AS createdMs,
          CAST(json_extract(p.data, '$.cost') AS REAL) AS cost
        FROM part p
        JOIN message m ON m.id = p.message_id
        WHERE json_valid(p.data)
          AND json_valid(m.data)
          AND json_extract(p.data, '$.type') = 'step-finish'
          AND json_type(p.data, '$.cost') IN ('integer', 'real')
          AND json_extract(m.data, '$.providerID') IN ('opencode', 'opencode-go')
          AND json_extract(m.data, '$.role') = 'assistant'
          AND NOT EXISTS (
            SELECT 1
            FROM message_costs
            WHERE message_costs.messageID = p.message_id
          )
    """

    // MARK: - Window computation

    private static func snapshot(rows: [UsageRow], now: Date) -> OpenCodeGoUsageSnapshot {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let sessionStart = nowMs - Int64(Self.fiveHours * 1000)
        let weekStart = self.startOfUTCWeek(now: now).timeIntervalSince1970 * 1000
        let weekStartMs = Int64(weekStart)
        let weekEndMs = weekStartMs + Int64(Self.week * 1000)
        let monthBounds = self.monthBounds(now: now, anchorMs: rows.map(\.createdMs).min())

        let sessionCost = self.sum(rows: rows, startMs: sessionStart, endMs: nowMs)
        let weeklyCost = self.sum(rows: rows, startMs: weekStartMs, endMs: weekEndMs)
        let monthlyCost = self.sum(rows: rows, startMs: monthBounds.startMs, endMs: monthBounds.endMs)

        return OpenCodeGoUsageSnapshot(
            rollingUsagePercent: self.percent(used: sessionCost, limit: self.limits.session),
            weeklyUsagePercent: self.percent(used: weeklyCost, limit: self.limits.weekly),
            monthlyUsagePercent: self.percent(used: monthlyCost, limit: self.limits.monthly),
            rollingResetInSec: self.rollingReset(rows: rows, nowMs: nowMs),
            weeklyResetInSec: max(0, Int((weekEndMs - nowMs) / 1000)),
            monthlyResetInSec: max(0, Int((monthBounds.endMs - nowMs) / 1000)),
            updatedAt: now)
    }

    private static func sum(rows: [UsageRow], startMs: Int64, endMs: Int64) -> Double {
        rows.reduce(0) { total, row in
            guard row.createdMs >= startMs, row.createdMs < endMs else { return total }
            return total + row.cost
        }
    }

    private static func percent(used: Double, limit: Double) -> Double {
        guard used.isFinite, limit > 0 else { return 0 }
        let value = max(0, min(100, used / limit * 100))
        return (value * 10).rounded() / 10
    }

    private static func rollingReset(rows: [UsageRow], nowMs: Int64) -> Int {
        let sessionStart = nowMs - Int64(Self.fiveHours * 1000)
        let oldest = rows
            .filter { $0.createdMs >= sessionStart && $0.createdMs < nowMs }
            .map(\.createdMs)
            .min() ?? nowMs
        return max(0, Int((oldest + Int64(Self.fiveHours * 1000) - nowMs) / 1000))
    }

    private static func startOfUTCWeek(now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return calendar.date(from: components) ?? now
    }

    private static func monthBounds(now: Date, anchorMs: Int64?) -> (startMs: Int64, endMs: Int64) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current

        guard let anchorMs else {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return (Int64(start.timeIntervalSince1970 * 1000), Int64(end.timeIntervalSince1970 * 1000))
        }

        let anchor = Date(timeIntervalSince1970: TimeInterval(anchorMs) / 1000)
        let anchorComponents = calendar.dateComponents([.day, .hour, .minute, .second, .nanosecond], from: anchor)
        let nowComponents = calendar.dateComponents([.year, .month], from: now)

        var startMonthComponents = nowComponents
        var start = self.anchoredMonth(calendar: calendar, month: startMonthComponents, anchor: anchorComponents)
        if start > now {
            guard let previous = calendar.date(byAdding: .month, value: -1, to: start) else {
                let end = self.anchoredMonth(
                    calendar: calendar,
                    month: self.monthComponents(after: startMonthComponents, calendar: calendar),
                    anchor: anchorComponents)
                return (Int64(start.timeIntervalSince1970 * 1000), Int64(end.timeIntervalSince1970 * 1000))
            }
            startMonthComponents = calendar.dateComponents([.year, .month], from: previous)
            start = self.anchoredMonth(calendar: calendar, month: startMonthComponents, anchor: anchorComponents)
        }
        let end = self.anchoredMonth(
            calendar: calendar,
            month: self.monthComponents(after: startMonthComponents, calendar: calendar),
            anchor: anchorComponents)
        return (Int64(start.timeIntervalSince1970 * 1000), Int64(end.timeIntervalSince1970 * 1000))
    }

    private static func monthComponents(after month: DateComponents, calendar: Calendar) -> DateComponents {
        let monthStart = calendar.date(from: month) ?? Date()
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        return calendar.dateComponents([.year, .month], from: nextMonth)
    }

    private static func anchoredMonth(
        calendar: Calendar,
        month: DateComponents,
        anchor: DateComponents) -> Date
    {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = month.year
        components.month = month.month
        components.day = anchor.day
        components.hour = anchor.hour
        components.minute = anchor.minute
        components.second = anchor.second
        components.nanosecond = anchor.nanosecond

        if let date = calendar.date(from: components),
           calendar.component(.month, from: date) == month.month
        {
            return date
        }

        components.day = calendar.range(of: .day, in: .month, for: calendar.date(from: month) ?? Date())?.count
        return calendar.date(from: components) ?? Date()
    }
}
