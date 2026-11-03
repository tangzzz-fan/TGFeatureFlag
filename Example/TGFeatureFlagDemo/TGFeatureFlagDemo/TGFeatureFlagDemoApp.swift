import SwiftUI
import TGFeatureFlag

/// Boolean switches. One value type per enum, so string configuration lives in `DemoConfig`.
///
/// The value type is part of the key, which is what makes `isEnabled` reject a string flag at
/// compile time instead of silently falling back to the default.
enum DemoFeature: String, TypedFeatureFlag, CaseIterable {
    case newHomeDesign = "feature_new_home"
    case socialTab = "feature_social_tab"
    case experimentalCheckout = "feature_checkout_v2"

    /// Deliberately misconfigured in `LocalProvider`: a Bool key whose provider returns a
    /// string. Reading it emits a `.typeMismatch` event and falls back to the default.
    case typeMismatchDemo = "feature_type_mismatch_demo"

    var typedDefaultValue: Bool { false }

    var description: String {
        switch self {
        case .newHomeDesign:
            return "New Home Design"
        case .socialTab:
            return "Social Tab"
        case .experimentalCheckout:
            return "Experimental Checkout"
        case .typeMismatchDemo:
            return "Type Mismatch Demo"
        }
    }
}

/// String configuration values.
enum DemoConfig: String, TypedFeatureFlag, CaseIterable {
    case apiBaseURL = "config_api_base_url"
    case welcomeMessage = "config_welcome_message"

    var typedDefaultValue: String {
        switch self {
        case .apiBaseURL:
            return "https://api.production.example"
        case .welcomeMessage:
            return "Feature flags are currently using local defaults."
        }
    }

    var description: String {
        switch self {
        case .apiBaseURL:
            return "API Base URL"
        case .welcomeMessage:
            return "Welcome Message"
        }
    }
}

/// Grouped keys get a `checkout.` prefix, which is also the key the rollout document uses.
enum CheckoutFeature: String, TypedFeatureFlag, GroupedFeatureFlag, CaseIterable {
    case v2Flow = "v2_flow"
    case newPayment = "new_payment"
    case expressShipping = "express_shipping"

    var typedDefaultValue: Bool { false }

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
    @State private var wiring = DemoWiring()

    var body: some Scene {
        WindowGroup {
            root
                .featureFlagService(wiring.service)
        }
    }

    /// Launch with `-debug-flags` to open the debug screen directly.
    ///
    /// Exists so the screen can be built and screenshotted from the command line (see
    /// `simulator-debugging-playbook.md`) without tapping through the navigation stack.
    @ViewBuilder
    private var root: some View {
        if ProcessInfo.processInfo.arguments.contains("-debug-flags") {
            NavigationStack {
                FeatureFlagDebugView<DemoFeature>()
            }
        } else {
            ContentView(wiring: wiring)
        }
    }
}
