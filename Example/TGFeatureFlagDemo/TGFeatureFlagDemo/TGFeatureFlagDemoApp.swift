import SwiftUI
import TGFeatureFlag

enum DemoFeature: String, FeatureFlagKey, CaseIterable {
    case newHomeDesign = "feature_new_home"
    case socialTab = "feature_social_tab"
    case experimentalCheckout = "feature_checkout_v2"
    case apiBaseURL = "config_api_base_url"
    case welcomeMessage = "config_welcome_message"

    var defaultValue: Any {
        switch self {
        case .newHomeDesign:
            return false
        case .socialTab:
            return false
        case .experimentalCheckout:
            return false
        case .apiBaseURL:
            return "https://api.production.example"
        case .welcomeMessage:
            return "Feature flags are currently using local defaults."
        }
    }

    var description: String {
        switch self {
        case .newHomeDesign:
            return "New Home Design"
        case .socialTab:
            return "Social Tab"
        case .experimentalCheckout:
            return "Experimental Checkout"
        case .apiBaseURL:
            return "API Base URL"
        case .welcomeMessage:
            return "Welcome Message"
        }
    }
}

enum CheckoutFeature: String, FeatureFlagKey, GroupedFeatureFlag, CaseIterable {
    case v2Flow = "v2_flow"
    case newPayment = "new_payment"
    case expressShipping = "express_shipping"

    var defaultValue: Any { false }

    var description: String {
        switch self {
        case .v2Flow:
            return "Checkout V2 Flow"
        case .newPayment:
            return "New Payment UI"
        case .expressShipping:
            return "Express Shipping"
        }
    }

    static var group: FeatureFlagGroup {
        FeatureFlagGroup(prefix: "checkout")
    }
}

@main
struct TGFeatureFlagDemoApp: App {
    @State private var service = TGFeatureFlagDemoApp.makeService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .featureFlagService(service)
        }
    }
}

private extension TGFeatureFlagDemoApp {
    static func makeService() -> FeatureFlagService {
        let service = FeatureFlagService()

        let debugProvider = DebugProvider()
        service.register(provider: debugProvider, priority: .highest)

        let rolloutProvider = RolloutProvider(userId: "demo-user-001")
        rolloutProvider.setRollout(for: CheckoutFeature.v2Flow, percentage: 75)
        rolloutProvider.setRollout(for: CheckoutFeature.newPayment, percentage: 40)
        rolloutProvider.setRollout(for: CheckoutFeature.expressShipping, percentage: 100)
        service.register(provider: rolloutProvider, priority: .custom(80))

        service.register(provider: MockRemoteProvider(), priority: .custom(60))
        service.register(provider: UserDefaultsProvider(), priority: .custom(40))

        let localProvider = LocalProvider(
            flags: [
                DemoFeature.newHomeDesign.rawValue: true,
                DemoFeature.experimentalCheckout.rawValue: false,
                DemoFeature.apiBaseURL.rawValue: "https://api.local.example",
                DemoFeature.welcomeMessage.rawValue: "Local provider is active until remote config refreshes."
            ]
        )
        service.register(provider: localProvider, priority: .lowest)

        return service
    }
}
