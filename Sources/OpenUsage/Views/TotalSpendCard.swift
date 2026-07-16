import AppKit
import SwiftUI

/// The dashboard's cross-provider Total Spend section: a native segmented period picker
/// (Today / Yesterday / Last 30 Days) over a donut ring whose segments are each provider's share of
/// the selected metric, with the total in the center and a ranked legend beside it. The title is a
/// pull-down menu for Cost / Cost/MTok / Tokens. Data comes from `TotalSpendAggregator` over
/// the same snapshots the provider cards render. Shown whenever any enabled provider tracks spend
/// (`LayoutStore.hasSpendCapableProvider`) and the toggle at the top of Settings is on; a period
/// (or metric) with nothing to show uses a quiet empty state instead of hiding the card.
struct TotalSpendCard: View {
    @Environment(LayoutStore.self) private var layout
    @Environment(WidgetDataStore.self) private var dataStore
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var pickerNamespace

    /// The selected period survives popover closes and relaunches, like the meter-style toggles.
    @AppStorage("openusage.totalSpend.period") private var periodRawValue = TotalSpendPeriod.today.rawValue
    /// The selected metric (Cost / Cost/MTok / Tokens) survives the same way.
    @AppStorage("openusage.totalSpend.metric") private var metricRawValue = TotalSpendMetric.cost.rawValue
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    /// Whether the inline 30-day trend chart is expanded below the ring.
    @State private var isTrendExpanded = true

    private var period: TotalSpendPeriod {
        TotalSpendPeriod(rawValue: periodRawValue) ?? .today
    }

    private var metric: TotalSpendMetric {
        TotalSpendMetric(rawValue: metricRawValue) ?? .cost
    }

    /// The spend-tile providers the card may aggregate — capability-based (see
    /// `LayoutStore.spendCapableProviders`), so a provider stays counted even when its own rows are
    /// hidden in Customize, and providers with merely similar-looking dollar rows never leak in.
    private var providers: [Provider] {
        layout.spendCapableProviders
    }

    private var total: TotalSpend {
        TotalSpendAggregator.total(for: period, providers: providers, snapshots: dataStore.snapshots)
    }

    private var projection: TotalSpendProjection {
        total.projection(for: metric)
    }

    /// Per-provider, per-day data for the 30-day stacked trend detail. The values come from each
    /// provider's raw `usageHistory`, so the chart reflects the selected metric: cost dollars, tokens,
    /// or cost per million tokens.
    private var trendDays: [TotalSpendTrendDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let offsets = (0...UsageHistoryWindow.previousDays).reversed()

        let providerDays: [(provider: Provider, days: [(label: String, value: Double)])] = providers.compactMap { provider -> (provider: Provider, days: [(label: String, value: Double)])? in
            guard let series = dataStore.snapshots[provider.id]?.usageHistory?.series.daily else { return nil }

            var valuesByKey: [String: Double] = [:]
            for entry in series {
                guard let key = trendDayKey(entry.date) else { continue }
                valuesByKey[key] = trendValue(for: entry)
            }

            let days: [(label: String, value: Double)] = offsets.compactMap { offset -> (label: String, value: Double)? in
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
                let key = DailyUsageAccumulator.dayKey(from: date, calendar: calendar)
                let label = Formatters.monthDayLabel(date)
                return (label, valuesByKey[key] ?? 0)
            }
            guard days.contains(where: { $0.value > 0 }) else { return nil }
            return (provider, days)
        }
        guard let first = providerDays.first else { return [] }

        let totals = providerDays.reduce(into: [String: Double]()) { result, pair in
            result[pair.provider.id] = pair.days.reduce(0) { $0 + $1.value }
        }

        return first.days.indices.map { index in
            var segments: [TotalSpendTrendSegment] = []
            for (provider, days) in providerDays {
                let value = days[index].value
                guard value > 0 else { continue }
                segments.append(TotalSpendTrendSegment(providerID: provider.id,
                                                       providerName: provider.displayName,
                                                       value: value))
            }
            segments.sort { (totals[$0.providerID] ?? 0) > (totals[$1.providerID] ?? 0) }
            let total = segments.reduce(0) { $0 + $1.value }
            return TotalSpendTrendDay(label: first.days[index].label, segments: segments, total: total)
        }
    }

    private func trendValue(for entry: DailyUsageEntry) -> Double {
        switch metric {
        case .tokens:
            return Double(entry.totalTokens)
        case .cost:
            return entry.costUSD ?? 0
        case .costPerMtok:
            guard entry.totalTokens > 0, let cost = entry.costUSD, cost > 0 else { return 0 }
            return (cost / Double(entry.totalTokens)) * 1_000_000
        }
    }

    private func trendDayKey(_ rawDate: String) -> String? {
        let value = rawDate.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return value
        }
        if let date = OpenUsageISO8601.date(from: value) {
            return DailyUsageAccumulator.dayKey(from: date)
        }
        if let match = value.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return String(value[match])
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density.headerToCardSpacing) {
            header
            card
        }
    }

    // MARK: - Header

    /// Section header matching the provider headers' scale: title menu leading, the share control
    /// trailing where a provider header shows its mark.
    private var header: some View {
        HStack(spacing: 5) {
            metricMenu
            Image(systemName: "info.circle")
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .hoverTooltip(infoTooltip)
            Spacer(minLength: 8)
            shareButton
        }
        .padding(.leading, 4)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
    }

    /// Title that is itself the metric switch — a plain pull-down with zero extra chrome.
    private var metricMenu: some View {
        Menu {
            ForEach(TotalSpendMetric.allCases) { option in
                Button {
                    metricRawValue = option.rawValue
                } label: {
                    if option == metric {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(metric.title)
                    .font(.system(size: density.headerPointSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Total Spend Metric")
        .accessibilityValue(metric.title)
    }

    /// Names the providers actually feeding the ring — the enabled spend-capable set — instead of a
    /// hardcoded list, so disabling a provider (or a new spend provider shipping) can't make the
    /// tooltip lie about what the total reflects.
    private var infoTooltip: String {
        let names = providers.map(\.displayName)
        return "Only includes \(names.formatted(.list(type: .and)))."
    }

    private var shareButton: some View {
        CopyFeedbackButton(accessibilityLabel: "Share \(metric.title) Screenshot") {
            ShareCardRenderer.shareTotalSpend(
                total: total,
                metric: metric,
                appearance: colorScheme,
                layout: layout
            )
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 12) {
            periodPicker
            if projection.isEmpty {
                emptyState
            } else {
                TotalSpendRingContent(projection: projection)
                if period == .last30, !trendDays.isEmpty {
                    trendToggleButton
                    if isTrendExpanded {
                        TotalSpendTrendInline(days: trendDays, metric: metric)
                            .transition(.opacity)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .cardSurface()
        .animation(Motion.spring, value: periodRawValue)
        .animation(Motion.spring, value: metricRawValue)
        .contextMenu {
            Button("Share Screenshot") {
                ShareCardRenderer.shareTotalSpend(
                    total: total,
                    metric: metric,
                    appearance: colorScheme,
                    layout: layout
                )
            }
        }
    }

    /// Bottom arrow that expands/collapses the inline 30-day stacked trend chart.
    private var trendToggleButton: some View {
        Button {
            withAnimation(Motion.spring) {
                isTrendExpanded.toggle()
            }
        } label: {
            Image(systemName: isTrendExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A capsule segmented switcher in the app's own design language (the footer's glass capsule
    /// controls), replacing the stock `.segmented` picker whose legacy rounded-rect chrome clashes
    /// with the Tahoe look. The selected segment is a Liquid Glass capsule (frosted material on
    /// macOS 15) that slides between segments via `matchedGeometryEffect`.
    private var periodPicker: some View {
        HStack(spacing: 2) {
            ForEach(TotalSpendPeriod.allCases) { candidate in
                periodSegment(candidate)
            }
        }
        .padding(3)
        .background(.quinary, in: Capsule())
        .frame(maxWidth: .infinity)
    }

    private func periodSegment(_ candidate: TotalSpendPeriod) -> some View {
        let isSelected = candidate == period
        return Button {
            periodRawValue = candidate.rawValue
        } label: {
            Text(candidate.shortLabel)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                Capsule()
                    .fill(.background)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    .matchedGeometryEffect(id: "totalSpendPeriod", in: pickerNamespace)
            }
        }
        .animation(Motion.spring, value: periodRawValue)
    }

    /// A metric/period combination with nothing to show mirrors the spend tiles' "No data" rule —
    /// never a fabricated zero ring.
    private var emptyState: some View {
        Text(metric.emptyMessage)
            .font(.system(size: density.supportingPointSize))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
    }
}

/// The ring + legend body, shared by the live card and the share-card export so the PNG can't drift
/// from what's on screen. Slices come ranked by the selected metric from `TotalSpend.projection`,
/// so the ring reads clockwise from 12 o'clock in the same order the legend reads top-down.
///
/// A period or metric switch **morphs** the arcs: each provider's slice slides and resizes to its
/// new share. Swift Charts' `SectorMark` can't do this — it matches sectors by array position when
/// animating, so any re-sort smears one provider's arc into another's color mid-morph (there is no
/// identity hook for sectors). The ring therefore draws its own sectors: one `RingSectorShape` per
/// provider, identity-keyed by provider ID, with the start/end angles as `animatableData`. SwiftUI
/// animates each provider's own arc, and the color can't swap because each arc view owns its
/// provider's color. The shape reproduces the SectorMark look — golden-ratio hole, hairline gaps,
/// rounded sector corners — so nothing changes visually at rest.
struct TotalSpendRingContent: View {
    let projection: TotalSpendProjection

    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    private static let ringDiameter: CGFloat = 104

    var body: some View {
        HStack(spacing: 18) {
            ring
            legend
        }
    }

    // MARK: - Ring

    /// Every slice is guaranteed at least this share of the circle, so a tiny provider next to a
    /// dominant one still shows a visible sliver instead of vanishing. Presentation-only — the
    /// legend and center keep the true amounts.
    private static let minimumSliceShare = 0.025

    private var ring: some View {
        ZStack {
            // Identity is the provider ID: a provider that exists in both states keeps its view,
            // so a switch animates that arc's angles. A provider entering or leaving fades in/out
            // (the default transition) while the survivors re-flow around it.
            ForEach(arcs) { arc in
                RingSectorShape(startFraction: arc.start, endFraction: arc.end)
                    .fill(TotalSpendPalette.color(for: arc.providerID))
            }
            centerLabel
        }
        .frame(width: Self.ringDiameter, height: Self.ringDiameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let center = formatValue(projection.centerValue, style: .full)
        switch projection.metric {
        case .cost:
            return "Total cost \(center) across \(projection.slices.count) providers"
        case .tokens:
            return "Total tokens \(center) across \(projection.slices.count) providers"
        case .costPerMtok:
            return "Blended cost per megatoken \(center) across \(projection.slices.count) providers"
        }
    }

    private struct RingArc: Identifiable, Equatable {
        let providerID: String
        var start: Double
        var end: Double

        var id: String { providerID }
    }

    /// The ranked slices as cumulative ring fractions, with the minimum-sliver floor applied and the
    /// result renormalized so the ring always closes exactly.
    private var arcs: [RingArc] {
        let totalDisplay = projection.slices.reduce(0) { $0 + $1.displayAmount }
        guard totalDisplay > 0 else { return [] }
        let floored = projection.slices.map { max($0.displayAmount / totalDisplay, Self.minimumSliceShare) }
        let sum = floored.reduce(0, +)
        guard sum > 0 else { return [] }

        var cursor = 0.0
        return zip(projection.slices, floored).map { slice, share in
            let width = share / sum
            defer { cursor += width }
            return RingArc(providerID: slice.provider.id, start: cursor, end: cursor + width)
        }
    }

    /// Quiet two-line center — short primary on top, unit underneath — so Cost/MTok (and big token
    /// totals) never force a long one-liner into the hole. Legend and tooltip still carry the
    /// exact one-line forms.
    private var centerLabel: some View {
        let center = MetricFormatter.totalSpendRingCenter(projection.centerValue, metric: projection.metric)
        let primarySize = Self.centerPrimarySize(for: center.primary)
        return VStack(spacing: 1) {
            Text(center.primary)
                .font(.system(size: primarySize, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(center.unit)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .hoverTooltip(centerTooltip)
    }

    /// Choose a smaller base font size for the ring center when Detailed Analytics produces long
    /// numbers (e.g. "26,841,749" tokens), while keeping the default compact forms at 13 pt.
    private static func centerPrimarySize(for text: String) -> CGFloat {
        guard DetailedAnalyticsSetting.isEnabled else { return 13 }
        let length = text.count
        if length <= 5 { return 13 }
        if length <= 7 { return 12 }
        if length <= 9 { return 11 }
        if length <= 11 { return 10 }
        return 9
    }

    private var centerTooltip: String {
        let exact = formatValue(projection.centerValue, style: .full)
        if projection.isEstimated, projection.metric.usesDollarEstimateNote {
            return "\(exact) · \(WidgetData.localEstimateNote)"
        }
        return exact
    }

    // MARK: - Legend

    /// Rows in the ring's ranked order (largest first), so scanning the ring clockwise from
    /// 12 o'clock matches reading the legend top-down.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(projection.slices) { slice in
                legendRow(slice)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendRow(_ slice: TotalSpendProjectedSlice) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(TotalSpendPalette.color(for: slice.provider.id))
                .frame(width: 8, height: 8)
            Text(slice.provider.displayName)
                .font(.system(size: density.supportingPointSize))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            // Tokens always abbreviate in the legend (12.4M), matching spend rows elsewhere —
            // `.full` would spill every digit. Cost modes keep cents via `.row` / `.full`.
            Text(formatValue(slice.displayAmount, style: legendValueStyle))
                .font(.system(size: density.supportingPointSize, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// Legend amounts: tokens always abbreviated; dollar modes keep exact cents like before.
    private var legendValueStyle: MetricFormatter.Style {
        switch projection.metric {
        case .tokens: .row
        case .cost, .costPerMtok: .full
        }
    }

    private func formatValue(_ value: Double, style: MetricFormatter.Style) -> String {
        switch projection.metric {
        case .cost:
            return MetricFormatter.number(value, kind: .dollars, style: style)
        case .tokens:
            return MetricFormatter.number(value, kind: .count, style: style)
        case .costPerMtok:
            return MetricFormatter.costPerMtok(value, style: style)
        }
    }
}

/// Stable per-provider brand tints for the Total Spend ring and legend — the one place the app maps
/// a provider to a color, so the chart, legend, and share card always agree. Colors are keyed by
/// provider ID only (never by rank or position), so a provider keeps its color across period
/// switches, re-sorts, and launches. Hexes come from the legacy edition's per-plugin `brandColor`
/// values; brands whose color is plain black (Cursor, Grok) get adaptive near-black/near-white
/// dynamic colors so they read on both appearances without both landing on the same gray.
enum TotalSpendPalette {
    private static let byProviderID: [String: Color] = [
        "claude": hex(0xDE7356),                             // Claude terracotta
        "codex": hex(0x10A37F),                              // OpenAI green (#10A37F)
        "cursor": dynamic(light: 0x13120A, dark: 0xF5F5F7),  // brand black (#13120A), flipped near-white in dark mode
        "grok": dynamic(light: 0x8E8E93, dark: 0x98989D),    // brand black, offset to gray next to Cursor
        "openrouter": hex(0x6467F2),                         // OpenRouter indigo
        "antigravity": hex(0x4285F4),                        // Google blue
        "copilot": hex(0xA855F7),                            // Copilot purple
        "amp": hex(0xF34E3F),
        "factory": dynamic(light: 0x48484A, dark: 0xC7C7CC),
        "kimi": hex(0x0A66FF),
        "minimax": hex(0xF5433C),
        "zai": dynamic(light: 0x2D2D2D, dark: 0xD1D1D6)
    ]

    /// Deterministic backstop hues for a provider that ships without a palette entry — keyed off the
    /// provider ID (not rank), so the color holds steady across periods and launches.
    private static let fallback: [Color] = [
        hex(0x34C759), hex(0x5856D6), hex(0xFF2D55), hex(0xA2845E)
    ]

    static func color(for providerID: String) -> Color {
        if let brand = byProviderID[providerID] { return brand }
        let stableHash = providerID.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return fallback[stableHash % fallback.count]
    }

    private static func hex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// A light/dark-adaptive color, for brands whose mark is pure black — invisible on a dark card
    /// unless flipped.
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
