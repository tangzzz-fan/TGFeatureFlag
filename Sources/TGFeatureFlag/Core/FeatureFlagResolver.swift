import Foundation
import os

/// A Sendable, non-MainActor resolver that materializes feature-flag values and snapshots.
///
/// Prefer this path for Redux / TGReduxKit-style apps: refresh providers, build a
/// `FeatureFlagSnapshot`, map it in an app adapter, then `dispatch(.loaded(...))`.
/// The Store remains the source of truth — do not also hang `@Observable FeatureFlagService`
/// in the environment as a second SoT.
///
/// Example adapter shape (app-owned, not in this package):
/// ```swift
/// struct TGFFFetchingAdapter: FeatureFlagFetching {
///     let resolver: FeatureFlagResolver
///     func fetchSnapshot() async -> AppFeatureFlagSnapshot {
///         _ = await resolver.refresh()
///         let remote = resolver.snapshot(for: AppFeature.allCases)
///         return AppFeatureFlagSnapshot(/* map keys → domain fields */)
///     }
/// }
/// ```
public final class FeatureFlagResolver: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var providerEntries: [FeatureFlagResolution.ProviderEntry] = []
        var logger: (any FeatureFlagLogger)?
    }

    public typealias Priority = FeatureFlagPriority

    public init() {}

    /// Registers a new provider with a given priority.
    public func register(provider: any FeatureFlagProvider, priority: Priority = .lowest) {
        lock.withLock { state in
            let entry = FeatureFlagResolution.ProviderEntry(
                priority: priority.rawValue,
                provider: provider
            )
            FeatureFlagResolution.insert(entry, into: &state.providerEntries)
        }
    }

    /// Sets a logger to observe all flag resolution events.
    public func setLogger(_ logger: (any FeatureFlagLogger)?) {
        lock.withLock { state in
            state.logger = logger
        }
    }

    /// Resolves the typed value for a feature flag.
    public func value<F: FeatureFlagKey>(for feature: F) -> FeatureFlagValue {
        let (entries, logger) = lock.withLock { state in
            (state.providerEntries, state.logger)
        }
        return FeatureFlagResolution.resolveValue(
            for: feature,
            providers: entries,
            logger: logger
        )
    }

    /// Checks if a feature is enabled (boolean flags).
    public func isEnabled<F: FeatureFlagKey>(_ feature: F) -> Bool {
        let resolved = value(for: feature)
        return FeatureFlagResolution.isEnabled(resolved, defaultValue: feature.defaultValue)
    }

    /// Builds a cold snapshot for the given keys.
    public func snapshot<S: Sequence>(
        for features: S
    ) -> FeatureFlagSnapshot where S.Element: FeatureFlagKey {
        let (entries, logger) = lock.withLock { state in
            (state.providerEntries, state.logger)
        }
        return FeatureFlagResolution.snapshot(
            for: features,
            providers: entries,
            logger: logger
        )
    }

    /// Refreshes all registered `AsyncFeatureFlagProvider` instances.
    /// - Returns: The number of providers that failed to refresh.
    @discardableResult
    public func refresh() async -> Int {
        let (entries, logger) = lock.withLock { state in
            (state.providerEntries, state.logger)
        }
        return await FeatureFlagResolution.refresh(providers: entries, logger: logger)
    }

    /// Helper to find a specific provider type.
    public func provider<T>(ofType type: T.Type) -> T? {
        let providers = lock.withLock { state in
            state.providerEntries.map(\FeatureFlagResolution.ProviderEntry.provider)
        }
        return providers.first { $0 is T } as? T
    }
}
