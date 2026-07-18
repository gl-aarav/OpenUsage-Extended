import SwiftUI

/// The branded, off-screen PNG for the Total Spend 30-day trend chart's share action.
/// The body draws `TotalSpendTrendInline` so the exported trend is exactly what the popover shows.
struct TotalSpendTrendShareCardView: View {
    let days: [TotalSpendTrendDay]
    let metric: TotalSpendMetric
    let appearance: ColorScheme

    var body: some View {
        ShareCardChrome(appearance: appearance) {
            headerRow
            DashboardMetricCard {
                TotalSpendTrendInline(days: days, metric: metric)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(metric.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Last 30 Days")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
