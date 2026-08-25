import SwiftUI

/// A container view that conditionally displays content based on a feature flag.
///
/// Observes `FeatureFlagService` in the environment (non-Redux / demo apps).
public struct FeatureGate<F: FeatureFlagKey, Content: View, Fallback: View>: View {

    private let feature: F
    private let content: () -> Content
    private let fallback: () -> Fallback

    @Environment(FeatureFlagService.self) private var service

    /// Creates a FeatureGate that reads from `FeatureFlagService` in the environment.
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

/// A FeatureGate that reads from an injected `FeatureFlagSnapshot` instead of
/// `@Environment(FeatureFlagService)`.
///
/// Use this in Redux / TGReduxKit apps where the Store (via snapshot) is the source of truth.
public struct SnapshotFeatureGate<F: FeatureFlagKey, Content: View, Fallback: View>: View {
    private let feature: F
    private let snapshot: FeatureFlagSnapshot
    private let content: () -> Content
    private let fallback: () -> Fallback

    public init(
        _ feature: F,
        snapshot: FeatureFlagSnapshot,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.feature = feature
        self.snapshot = snapshot
        self.content = content
        self.fallback = fallback
    }

    public var body: some View {
        if snapshot.isEnabled(feature) {
            content()
        } else {
            fallback()
        }
    }
}

public extension SnapshotFeatureGate where Fallback == EmptyView {
    init(
        _ feature: F,
        snapshot: FeatureFlagSnapshot,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(feature, snapshot: snapshot, content: content, fallback: { EmptyView() })
    }
}
