import SwiftUI
import TGFeatureFlag

// Define Feature Flags
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

@main
struct TGFeatureFlagDemoApp: App {
    @State private var service: FeatureFlagService
    
    init() {
        let s = FeatureFlagService()
        
        // 1. Debug Provider (Highest Priority) - For runtime toggling
        s.register(provider: DebugProvider(), priority: .highest)
        
        // 2. Mock Remote Provider (Medium Priority) - Simulating Server Side Config
        // This overrides UserDefaults and Local defaults in this demo setup logic,
        // but typically you might want User Settings > Remote.
        // For this demo to show "Remote overrides fixed in app", we place it here.
        // Since we are using .lowest (append), we need to add them in order of precedence if we want to control order precisely.
        // Current order in array will be: [Debug] -> append(Remote) -> [Debug, Remote] -> append(UserDefaults) ...
        // Wait, 'lowest' appends to the END.
        // So:
        // 1. Debug (inserted at 0) -> [Debug]
        // 2. Remote (appended) -> [Debug, Remote]
        // 3. UserDefaults (appended) -> [Debug, Remote, UserDefaults]
        // 4. Local (appended) -> [Debug, Remote, UserDefaults, Local]
        // Priority Chain: Debug > Remote > UserDefaults > Local
        
        s.register(provider: MockRemoteProvider(), priority: .lowest)
        
        // 3. UserDefaults (Lower Priority)
        s.register(provider: UserDefaultsProvider(), priority: .lowest)
        
        // 4. Local Default (Lowest Priority) - Fallback
        s.register(provider: LocalProvider(enabledFeatures: [DemoFeature.newHomeDesign]), priority: .lowest)
        
        _service = State(initialValue: s)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .featureFlagService(service)
        }
    }
}
