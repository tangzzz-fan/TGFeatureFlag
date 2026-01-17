import SwiftUI

public extension View {
    /// Injects the FeatureFlagService into the view hierarchy.
    /// Call this at the root of your app (e.g., inside `WindowGroup`).
    func featureFlagService(_ service: FeatureFlagService) -> some View {
        self.environment(service)
    }
}
