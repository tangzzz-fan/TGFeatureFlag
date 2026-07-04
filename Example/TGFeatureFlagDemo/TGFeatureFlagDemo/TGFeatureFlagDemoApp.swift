import SwiftUI
import TGFeatureFlag

// MARK: - Feature Flags

/// Standard (ungrouped) feature flags used across the demo.
enum DemoFeature: String, FeatureFlagKey, CaseIterable {
    case newHomeDesign = "feature_new_home"
    case socialTab = "feature_social_tab"
    case experimentalCheckout = "feature_checkout_v2"
    case detailedNavigation = "feature_detailed_navigation"
    
    // Configuration Keys
    case apiBaseUrl = "config_api_base_url"
    
    var defaultValue: Any {
        switch self {
        case .newHomeDesign: return true
        case .socialTab: return false
        case .experimentalCheckout: return false
        case .detailedNavigation: return true
        case .apiBaseUrl: return "https://api.production.com"
        }
    }
    
    var description: String {
        switch self {
        case .newHomeDesign: return "New Home UI"
        case .socialTab: return "Social Tab"
        case .experimentalCheckout: return "Checkout V2 Flow"
        case .detailedNavigation: return "Detailed View Navigation"
        case .apiBaseUrl: return "API Base URL"
        }
    }
}

// MARK: - Grouped Feature Flags (FeatureFlagGroup Demo)

/// Demonstrates `GroupedFeatureFlag` — keys are resolved with a namespace prefix
/// (e.g. `"checkout.v2Flow"` instead of just `"v2Flow"`).
enum CheckoutFeature: String, FeatureFlagKey, GroupedFeatureFlag, CaseIterable {
    case v2Flow = "v2Flow"
    case newPayment = "newPayment"
    case expressShipping = "expressShipping"
    
    var defaultValue: Any { false }
    
    var description: String {
        switch self {
        case .v2Flow: return "Checkout V2 Flow"
        case .newPayment: return "New Payment UI"
        case .expressShipping: return "Express Shipping"
        }
    }
    
    static var group: FeatureFlagGroup {
        FeatureFlagGroup(prefix: "checkout")
    }
}

// MARK: - Demo Logger (FeatureFlagLogger Demo)

/// A simple in-memory logger that records flag resolution events for display in the UI.
@Observable
final class DemoLogger: FeatureFlagLogger, @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [LogEntry] = []
    
    struct LogEntry: Identifiable, Sendable {
        let id = UUID()
        let flag: String
        let provider: String
        let value: String
        let timestamp: Date
    }
    
    var entries: [LogEntry] {
        lock.withLock { _entries }
    }
    
    func log(flag: String, resolvedBy provider: String?, value: Any?) {
        let entry = LogEntry(
            flag: flag,
            provider: provider ?? "default",
            value: value.map { "\($0)" } ?? "nil",
            timestamp: Date()
        )
        lock.withLock {
            _entries.insert(entry, at: 0)
            if _entries.count > 50 { _entries.removeLast() }
        }
    }
}

// MARK: - App Entry Point

@main
struct TGFeatureFlagDemoApp: App {
    @State private var service: FeatureFlagService
    let demoLogger = DemoLogger()
    
    init() {
        let s = FeatureFlagService()
        
        // Attach diagnostic logger
        s.setLogger(demoLogger)
        
        // 1. Debug Provider (Highest Priority) - For runtime toggling
        s.register(provider: DebugProvider(), priority: .highest)
        
        // 2. Rollout Provider (Custom Priority 80) - Percentage-based rollout
        let rollout = RolloutProvider(userId: "demo-user-001")
        rollout.setRollout(for: CheckoutFeature.v2Flow, percentage: 75)
        rollout.setRollout(for: CheckoutFeature.newPayment, percentage: 50)
        rollout.setRollout(for: CheckoutFeature.expressShipping, percentage: 100)
        s.register(provider: rollout, priority: .custom(80))
        
        // 3. Mock Remote Provider (Medium Priority) - Simulating Server Config
        s.register(provider: MockRemoteProvider(), priority: .custom(60))
        
        // 4. UserDefaults (Lower Priority)
        s.register(provider: UserDefaultsProvider(), priority: .custom(40))
        
        // 5. Local Default (Lowest Priority) - Fallback
        s.register(provider: LocalProvider(enabledFeatures: [DemoFeature.newHomeDesign]), priority: .lowest)
        
        _service = State(initialValue: s)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .featureFlagService(service)
                .environment(demoLogger)
        }
    }
}
