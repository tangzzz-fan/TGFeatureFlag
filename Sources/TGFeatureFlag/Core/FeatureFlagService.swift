import Foundation
import Observation

/// The central manager for Feature Flags in non-Redux / demo apps.
///
/// This service aggregates values from multiple `FeatureFlagProvider` sources and uses
/// Observation (`@Observable`) to update SwiftUI views.
///
/// For Redux / TGReduxKit apps, prefer `FeatureFlagResolver` + `FeatureFlagSnapshot`
/// dispatched into the Store (Store is the source of truth). Do not use this service
/// alongside the Store as a second SoT.
@MainActor
@Observable
public final class FeatureFlagService {

    /// Internal storage: providers sorted by priority (highest first).
    private var providerEntries: [FeatureFlagResolution.ProviderEntry] = []

    /// Computed list of providers for backward compatibility.
    private var providers: [any FeatureFlagProvider] {
        providerEntries.map(\.provider)
    }

    /// Optional logger for observing flag resolution.
    private var logger: (any FeatureFlagLogger)?

    /// A version counter to force UI updates when external sources (like UserDefaults) change.
    private var _updateTrigger: Int = 0

    public typealias Priority = FeatureFlagPriority

    public init() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.triggerUpdate()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Registers a new provider with a given priority.
    public func register(provider: any FeatureFlagProvider, priority: Priority = .lowest) {
        let entry = FeatureFlagResolution.ProviderEntry(
            priority: priority.rawValue,
            provider: provider
        )
        FeatureFlagResolution.insert(entry, into: &providerEntries)
    }

    /// Sets a logger to observe all flag resolution events.
    public func setLogger(_ logger: (any FeatureFlagLogger)?) {
        self.logger = logger
    }

    /// Checks if a feature is enabled (Boolean only).
    public func isEnabled<F: FeatureFlagKey>(_ feature: F) -> Bool {
        let resolved = value(for: feature)
        return FeatureFlagResolution.isEnabled(resolved, defaultValue: feature.defaultValue)
    }

    /// Retrieves the typed value for a feature flag.
    public func value<F: FeatureFlagKey>(for feature: F) -> FeatureFlagValue {
        // Access _updateTrigger to register dependency for Observation
        _ = _updateTrigger

        return FeatureFlagResolution.resolveValue(
            for: feature,
            providers: providerEntries,
            logger: logger
        )
    }

    /// Convenience boolean accessor. Falls back to the flag default when non-boolean.
    public func boolValue<F: FeatureFlagKey>(for feature: F) -> Bool {
        isEnabled(feature)
    }

    /// Convenience string accessor. Falls back to the flag default when missing/mismatched.
    public func stringValue<F: FeatureFlagKey>(for feature: F) -> String {
        value(for: feature).stringValue
            ?? feature.defaultValue.stringValue
            ?? ""
    }

    /// Convenience int accessor. Falls back to the flag default when missing/mismatched.
    public func intValue<F: FeatureFlagKey>(for feature: F) -> Int {
        value(for: feature).intValue
            ?? feature.defaultValue.intValue
            ?? 0
    }

    /// Convenience double accessor. Falls back to the flag default when missing/mismatched.
    public func doubleValue<F: FeatureFlagKey>(for feature: F) -> Double {
        value(for: feature).doubleValue
            ?? feature.defaultValue.doubleValue
            ?? 0
    }

    /// Builds a cold snapshot for the given keys (also useful from the Service path).
    public func snapshot<S: Sequence>(
        for features: S
    ) -> FeatureFlagSnapshot where S.Element: FeatureFlagKey {
        _ = _updateTrigger
        return FeatureFlagResolution.snapshot(
            for: features,
            providers: providerEntries,
            logger: logger
        )
    }

    /// Manually triggers an update notification.
    public func triggerUpdate() {
        _updateTrigger += 1
    }

    /// Refreshes all registered `AsyncFeatureFlagProvider` instances.
    /// - Returns: The number of providers that failed to refresh.
    @discardableResult
    public func refresh() async -> Int {
        let failureCount = await FeatureFlagResolution.refresh(
            providers: providerEntries,
            logger: logger
        )
        triggerUpdate()
        return failureCount
    }

    /// Helper to find a specific provider type.
    public func provider<T>(ofType type: T.Type) -> T? {
        providers.first { $0 is T } as? T
    }
}
