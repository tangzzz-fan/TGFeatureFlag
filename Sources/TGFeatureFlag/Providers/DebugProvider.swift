import Foundation
import os

/// A mutable provider intended for debug builds.
/// Allows runtime toggling of feature flags to test different states.
public final class DebugProvider: FeatureFlagProvider, Sendable {
    public let name: String = "Debug Override"

    private let lock = OSAllocatedUnfairLock(initialState: [String: FeatureFlagValue]())

    public init() {}

    public func value(for key: String) -> FeatureFlagValue? {
        lock.withLock { overrides in
            overrides[key]
        }
    }

    /// Overrides a feature flag value.
    /// Uses `feature.lookupKey` so grouped flags match service/resolver lookups.
    public func setOverride<F: FeatureFlagKey>(for feature: F, value: FeatureFlagValue?) {
        let key = feature.lookupKey
        lock.withLock { overrides in
            if let value {
                overrides[key] = value
            } else {
                overrides.removeValue(forKey: key)
            }
        }
    }

    /// Clears all overrides.
    public func reset() {
        lock.withLock { overrides in
            overrides.removeAll()
        }
    }
}
