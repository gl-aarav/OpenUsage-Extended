import Foundation

enum OpenCodeGoUsageMapper {
    static func map(_ snapshot: OpenCodeGoUsageSnapshot, now: Date) -> [MetricLine] {
        var lines: [MetricLine] = []

        let rollingReset = snapshot.updatedAt.addingTimeInterval(TimeInterval(snapshot.rollingResetInSec))
        lines.append(.progress(
            label: "Rolling",
            used: snapshot.rollingUsagePercent,
            limit: 100,
            format: .percent,
            resetsAt: rollingReset,
            periodDurationMs: MetricPeriod.sessionMs
        ))

        let weeklyReset = snapshot.updatedAt.addingTimeInterval(TimeInterval(snapshot.weeklyResetInSec))
        lines.append(.progress(
            label: "Weekly",
            used: snapshot.weeklyUsagePercent,
            limit: 100,
            format: .percent,
            resetsAt: weeklyReset,
            periodDurationMs: MetricPeriod.weekMs
        ))

        let monthlyReset = snapshot.updatedAt.addingTimeInterval(TimeInterval(snapshot.monthlyResetInSec))
        lines.append(.progress(
            label: "Monthly",
            used: snapshot.monthlyUsagePercent,
            limit: 100,
            format: .percent,
            resetsAt: monthlyReset,
            periodDurationMs: MetricPeriod.monthMs
        ))

        return lines
    }
}
