import SwiftUI

/// One provider's share of a single day's total in the cross-provider 30-day trend.
struct TotalSpendTrendSegment: Identifiable, Equatable {
    let providerID: String
    let providerName: String
    let value: Double
    var id: String { providerID }
}

/// A single day in the stacked trend: its axis label, the per-provider segments, and the summed total.
struct TotalSpendTrendDay: Identifiable, Equatable {
    let label: String
    let segments: [TotalSpendTrendSegment]
    let total: Double
    var id: String { label }
}

/// Detail-on-demand popover for the Total Spend card's 30-day period: a stacked bar chart with one
/// segment per provider, so the daily total is shown split by contributor. Hovering a day highlights
/// it and swaps the header readout to that day's total.
struct TotalSpendTrendDetail: View {
    let days: [TotalSpendTrendDay]
    let metric: TotalSpendMetric
    /// Reports whether the cursor is inside the popover, so the trigger can keep it open while the user
    /// moves from the segment into the chart, and close it once they leave both.
    var onHoverChange: (Bool) -> Void = { _ in }

    @State private var activeIndex: Int?

    private static let chartHeight: CGFloat = 76
    private static let width: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            chart
            axis
            legend
        }
        .padding(12)
        .frame(width: Self.width)
        // A refresh can replace `days` while the popover is open; drop the selection so the highlight
        // and readout never point at a day that shifted out from under the cursor.
        .onChange(of: days) { activeIndex = nil }
        .onContinuousHover { phase in
            switch phase {
            case .active: onHoverChange(true)
            case .ended: onHoverChange(false); activeIndex = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(chartTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(readout)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var chart: some View {
        let maxValue = max(1, days.map(\.total).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 1) {
            ForEach(days.indices, id: \.self) { index in
                dayColumn(day: days[index], index: index, maxValue: maxValue)
            }
        }
        .frame(height: Self.chartHeight)
        // Clear the selection when the cursor leaves the bars for the header/axis/legend (still inside the
        // popover), so the readout falls back to the peak instead of freezing on the last bar.
        .onContinuousHover { phase in if case .ended = phase { activeIndex = nil } }
        .animation(.easeOut(duration: 0.12), value: activeIndex)
    }

    private func dayColumn(day: TotalSpendTrendDay, index: Int, maxValue: Double) -> some View {
        VStack(spacing: 0) {
            ForEach(day.segments) { segment in
                Rectangle()
                    .fill(TotalSpendPalette.color(for: segment.providerID))
                    .frame(height: barHeight(segment.value, max: maxValue))
                    .opacity(activeIndex == nil || activeIndex == index ? 1 : 0.35)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active = phase { activeIndex = index }
        }
        .hoverTooltip(key: day.label) {
            tooltipContent(for: day)
        }
    }

    private func tooltipContent(for day: TotalSpendTrendDay) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(day.label) · \(valueText(day.total))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            ForEach(day.segments) { segment in
                HStack(spacing: 5) {
                    Circle()
                        .fill(TotalSpendPalette.color(for: segment.providerID))
                        .frame(width: 7, height: 7)
                    Text(segment.providerName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(valueText(segment.value))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
        }
        .fixedSize()
    }

    private var axis: some View {
        HStack {
            Text(days.first?.label ?? "")
            Spacer()
            Text(days.last?.label ?? "")
        }
        .font(.system(size: 10))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(days.flatMap(\.segments).uniqueSegments().sortedByTotal(days: days), id: \.providerID) { segment in
                HStack(spacing: 4) {
                    Circle()
                        .fill(TotalSpendPalette.color(for: segment.providerID))
                        .frame(width: 6, height: 6)
                    Text(segment.providerName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var chartTitle: String {
        switch metric {
        case .cost: return "30 Day Cost"
        case .costPerMtok: return "30 Day Cost/MTok"
        case .tokens: return "30 Day Tokens"
        }
    }

    private func valueText(_ value: Double) -> String {
        switch metric {
        case .cost: return MetricFormatter.number(value, kind: .dollars, style: .row)
        case .costPerMtok: return MetricFormatter.costPerMtok(value, style: .row)
        case .tokens: return MetricFormatter.number(value, kind: .count, style: .row) + " tokens"
        }
    }

    private var peakIndex: Int? { days.indices.max { days[$0].total < days[$1].total } }

    /// The hovered day, or the peak when nothing is hovered — the one figure the bars can't label.
    private var readout: String {
        if let activeIndex, days.indices.contains(activeIndex) {
            return "\(days[activeIndex].label) · \(valueText(days[activeIndex].total))"
        }
        if let peakIndex { return "peak \(valueText(days[peakIndex].total))" }
        return ""
    }

    private func barHeight(_ value: Double, max maxValue: Double) -> CGFloat {
        guard value > 0 else { return 0 }
        return max(Self.chartHeight * 0.06, Self.chartHeight * min(1, value / maxValue))
    }
}

/// Inline expanded 30-day trend shown inside the Total Spend card when the 30-day period is selected.
/// Matches the Usage Trend row layout: header, full-width stacked bar chart, axis, and provider legend.
struct TotalSpendTrendInline: View {
    let days: [TotalSpendTrendDay]
    let metric: TotalSpendMetric

    @State private var activeIndex: Int?

    private static let chartHeight: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            chart
            axis
            legend
        }
        .onChange(of: days) { activeIndex = nil }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(chartTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(readout)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var chartTitle: String {
        switch metric {
        case .cost: return "30 Day Cost"
        case .costPerMtok: return "30 Day Cost/MTok"
        case .tokens: return "30 Day Tokens"
        }
    }

    private func valueText(_ value: Double) -> String {
        switch metric {
        case .cost: return MetricFormatter.number(value, kind: .dollars, style: .row)
        case .costPerMtok: return MetricFormatter.costPerMtok(value, style: .row)
        case .tokens: return MetricFormatter.number(value, kind: .count, style: .row) + " tokens"
        }
    }

    /// The hovered day's total, or the peak when nothing is hovered. The per-provider breakdown now
    /// lives in the hover tooltip.
    private var readout: String {
        if let activeIndex, days.indices.contains(activeIndex) {
            return "\(days[activeIndex].label) · \(valueText(days[activeIndex].total))"
        }
        if let peakIndex { return "peak \(valueText(days[peakIndex].total))" }
        return ""
    }

    private var chart: some View {
        let maxValue = max(1, days.map(\.total).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 1) {
            ForEach(days.indices, id: \.self) { index in
                dayColumn(day: days[index], index: index, maxValue: maxValue)
            }
        }
        .frame(height: Self.chartHeight)
        .onContinuousHover { phase in if case .ended = phase { activeIndex = nil } }
        .animation(.easeOut(duration: 0.12), value: activeIndex)
    }

    private func dayColumn(day: TotalSpendTrendDay, index: Int, maxValue: Double) -> some View {
        VStack(spacing: 0) {
            ForEach(day.segments) { segment in
                Rectangle()
                    .fill(TotalSpendPalette.color(for: segment.providerID))
                    .frame(height: barHeight(segment.value, max: maxValue))
                    .opacity(activeIndex == nil || activeIndex == index ? 1 : 0.35)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active = phase { activeIndex = index }
        }
        .hoverTooltip(key: day.label) {
            tooltipContent(for: day)
        }
    }

    private func tooltipContent(for day: TotalSpendTrendDay) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(day.label) · \(valueText(day.total))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            ForEach(day.segments) { segment in
                HStack(spacing: 5) {
                    Circle()
                        .fill(TotalSpendPalette.color(for: segment.providerID))
                        .frame(width: 7, height: 7)
                    Text(segment.providerName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(valueText(segment.value))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
        }
        .fixedSize()
    }

    private var axis: some View {
        HStack {
            Text(days.first?.label ?? "")
            Spacer()
            Text(days.last?.label ?? "")
        }
        .font(.system(size: 10))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(days.flatMap(\.segments).uniqueSegments().sortedByTotal(days: days), id: \.providerID) { segment in
                HStack(spacing: 4) {
                    Circle()
                        .fill(TotalSpendPalette.color(for: segment.providerID))
                        .frame(width: 6, height: 6)
                    Text(segment.providerName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var peakIndex: Int? { days.indices.max { days[$0].total < days[$1].total } }

    private func barHeight(_ value: Double, max maxValue: Double) -> CGFloat {
        guard value > 0 else { return 0 }
        return max(Self.chartHeight * 0.06, Self.chartHeight * min(1, value / maxValue))
    }
}

private extension Array where Element == TotalSpendTrendSegment {
    /// Unique segments by provider ID, preserving the first encountered name.
    func uniqueSegments() -> [TotalSpendTrendSegment] {
        var seen = Set<String>()
        return filter { segment in
            guard !seen.contains(segment.providerID) else { return false }
            seen.insert(segment.providerID)
            return true
        }
    }

    /// Sort by each provider's total contribution across the supplied days, largest first.
    func sortedByTotal(days: [TotalSpendTrendDay]) -> [TotalSpendTrendSegment] {
        let totals = days.reduce(into: [String: Double]()) { result, day in
            for segment in day.segments {
                result[segment.providerID, default: 0] += segment.value
            }
        }
        return sorted { (totals[$0.providerID] ?? 0) > (totals[$1.providerID] ?? 0) }
    }
}
