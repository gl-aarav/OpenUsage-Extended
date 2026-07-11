import Foundation

@MainActor
final class OpenCodeGoProvider: ProviderRuntime {
    let provider = Provider(
        id: "opencodego",
        displayName: "OpenCode Go",
        icon: .providerMark("opencodego"),
        links: [
            ProviderLink(label: "Dashboard", url: "https://opencode.ai")
        ]
    )

    let authStore: OpenCodeGoAuthStore
    let usageReader: OpenCodeGoUsageReader
    let now: @Sendable () -> Date

    init(
        authStore: OpenCodeGoAuthStore = OpenCodeGoAuthStore(),
        usageReader: OpenCodeGoUsageReader = OpenCodeGoUsageReader(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.authStore = authStore
        self.usageReader = usageReader
        self.now = now
    }

    var widgetDescriptors: [WidgetDescriptor] {
        [
            .percent(id: "opencodego.rolling", provider: provider, title: "Rolling",
                     metricLabel: "Rolling"),
            .percent(id: "opencodego.weekly", provider: provider, title: "Weekly",
                     metricLabel: "Weekly"),
            .percent(id: "opencodego.monthly", provider: provider, title: "Monthly",
                     metricLabel: "Monthly")
        ]
    }

    func hasLocalCredentials() async -> Bool {
        await loadOffMainActor { [authStore] in
            authStore.hasAuthKey() && authStore.hasDatabase()
        }
    }

    func refresh() async -> ProviderSnapshot {
        let hasCredentials = await loadOffMainActor { [authStore] in
            authStore.hasAuthKey() && authStore.hasDatabase()
        }
        guard hasCredentials else {
            return ProviderSnapshot.error(provider: provider, error: OpenCodeGoAuthError.notLoggedIn)
        }

        do {
            let snapshot = try await loadOffMainActor { [usageReader, now] in
                try usageReader.fetch(now: now())
            }
            let lines = OpenCodeGoUsageMapper.map(snapshot, now: now())
            return ProviderSnapshot.make(provider: provider, plan: nil, lines: lines, refreshedAt: now())
        } catch let error as OpenCodeGoUsageError {
            return ProviderSnapshot.error(provider: provider, error: error)
        } catch {
            return ProviderSnapshot.error(provider: provider, error: OpenCodeGoUsageError.sqliteFailed(error.localizedDescription))
        }
    }
}
