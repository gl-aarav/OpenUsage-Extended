import Foundation

/// Whether the dashboard and menu bar render numeric values with two decimal digits instead of
/// the default compact/rounded forms. Off by default so the tray and popover stay skimmable.
enum DetailedAnalyticsSetting {
    static let key = "detailedAnalytics"

    #if DEBUG
    nonisolated(unsafe) static var isEnabledOverride: Bool? = nil
    #endif

    static var isEnabled: Bool {
        #if DEBUG
        if let override = isEnabledOverride { return override }
        #endif
        return UserDefaults.standard.bool(forKey: key, default: false)
    }
}
