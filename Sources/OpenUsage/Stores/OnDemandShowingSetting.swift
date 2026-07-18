import Foundation

/// Whether the dashboard shows unstarred metrics for providers only when they have data.
/// Off by default. Starred metrics are always shown even if they have no data.
enum OnDemandShowingSetting {
    static let key = "onDemandShowing"

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
