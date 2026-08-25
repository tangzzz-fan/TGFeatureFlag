import Foundation
import os
import TGFeatureFlag

/// A mock provider simulating a remote configuration service (e.g. Firebase Remote Config).
///
/// Implements `AsyncFeatureFlagProvider` for async refresh via `FeatureFlagService.refresh()`
/// or `FeatureFlagResolver.refresh()`.
public final class MockRemoteProvider: AsyncFeatureFlagProvider, Sendable {
    public let name: String = "Remote Config"

    private let lock = OSAllocatedUnfairLock(initialState: [String: FeatureFlagValue]())

    public init() {}

    public func value(for key: String) -> FeatureFlagValue? {
        lock.withLock { flags in
            flags[key]
        }
    }

    /// Async fetch implementation for resolver/service refresh.
    public func fetchValues() async throws {
        try await Task.sleep(for: .seconds(1.5))

        let newConfig: [String: FeatureFlagValue] = [
            "feature_new_home": .bool(true),
            "feature_social_tab": .bool(true),
            "config_api_base_url": .string("https://api.staging.remote.com"),
            "feature_detailed_navigation": .bool(true)
        ]

        lock.withLock { flags in
            flags = newConfig
        }
    }

    /// Legacy callback-based fetch for backward compatibility.
    public func fetchRemoteConfig(completion: @escaping () -> Void) {
        Task {
            try? await fetchValues()
            await MainActor.run { completion() }
        }
    }
}
