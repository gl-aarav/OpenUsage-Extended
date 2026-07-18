import XCTest
import SwiftUI
@testable import OpenUsage

final class OnDemandShowingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: OnDemandShowingSetting.key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: OnDemandShowingSetting.key)
        super.tearDown()
    }

    func testDefaultSettingIsDisabled() {
        XCTAssertFalse(OnDemandShowingSetting.isEnabled)
    }

    func testSettingObeysUserDefaults() {
        UserDefaults.standard.set(true, forKey: OnDemandShowingSetting.key)
        XCTAssertTrue(OnDemandShowingSetting.isEnabled)

        UserDefaults.standard.set(false, forKey: OnDemandShowingSetting.key)
        XCTAssertFalse(OnDemandShowingSetting.isEnabled)
    }

    @MainActor
    func testShareCardRendersWithSetting() throws {
        let provider = MockData.claude
        let widgets = MockData.descriptors(for: provider.id).map { PlacedWidget(descriptorID: $0.id) }
        let group = ProviderGroup(provider: provider, alwaysShownWidgets: widgets, expandedWidgets: [])
        
        let defaults = UserDefaults(suiteName: "OnDemandTests")!
        defaults.removePersistentDomain(forName: "OnDemandTests")
        
        let layout = LayoutStore(registry: .mock, defaults: defaults, storageKey: "layout")
        let dataStore = WidgetDataStore(registry: .mock, providers: [], defaults: defaults)
        
        // Initially, share succeeds
        let successDefault = ShareCardRenderer.image(for: ShareCardView(
            provider: provider,
            plan: nil,
            rows: widgets.compactMap { dataStore.data(for: layout.descriptor(for: $0)!) },
            appearance: .light
        ))
        XCTAssertNotNil(successDefault)
        
        // Turn setting on
        UserDefaults.standard.set(true, forKey: OnDemandShowingSetting.key)
        
        // Test that rendering doesn't crash with the setting active
        let successWithSetting = ShareCardRenderer.image(for: ShareCardView(
            provider: provider,
            plan: nil,
            rows: widgets.compactMap { w -> WidgetData? in
                let descriptor = layout.descriptor(for: w)!
                let data = dataStore.data(for: descriptor)
                if !layout.isPinned(descriptor.id) && !data.hasData {
                    return nil
                }
                return data
            },
            appearance: .light
        ))
        XCTAssertNotNil(successWithSetting)
    }
}
