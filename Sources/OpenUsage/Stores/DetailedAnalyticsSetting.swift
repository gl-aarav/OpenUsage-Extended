import Foundation

/// Whether the dashboard and menu bar render numeric values with two decimal digits instead of
/// the default compact/rounded forms. Off by default so the tray and popover stay skimmable.
enum DetailedAnalyticsSetting {
    static let key = "detailedAnalytics"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: key, default: false)
    }
}
