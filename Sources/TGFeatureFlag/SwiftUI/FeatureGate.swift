import SwiftUI

/// A container view that conditionally displays content based on a feature flag.
///
/// It observes the `FeatureFlagService` in the environment, ensuring the view updates
/// automatically if the flag value changes (e.g., via DebugProvider).
public struct FeatureGate<F: FeatureFlagKey, Content: View, Fallback: View>: View {
    
    private let feature: F
    private let content: () -> Content
    private let fallback: () -> Fallback
    
    // We expect the service to be injected via .environment
    @Environment(FeatureFlagService.self) private var service
    
    /// Creates a FeatureGate.
    /// - Parameters:
    ///   - feature: The feature flag to check.
    ///   - content: The view to show if the feature is ENABLED.
    ///   - fallback: The view to show if the feature is DISABLED.
    public init(
        _ feature: F,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.feature = feature
        self.content = content
        self.fallback = fallback
    }
    
    public var body: some View {
        if service.isEnabled(feature) {
            content()
        } else {
            fallback()
        }
    }
}

public extension FeatureGate where Fallback == EmptyView {
    /// Convenience initializer for when no fallback is needed.
    init(
        _ feature: F,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(feature, content: content, fallback: { EmptyView() })
    }
}
