import Foundation
import os

/// A provider that enables percentage-based feature flag rollouts.
///
/// Uses a deterministic FNV-1a hash of a user identifier to decide whether a feature
/// is enabled for a given user. This ensures the same user consistently gets
/// the same result for a given rollout percentage across process launches.
///
/// Example:
/// ```swift
/// let rollout = RolloutProvider(userId: "user-123")
/// rollout.setRollout(for: "new_feature", percentage: 50) // 50% rollout
/// resolver.register(provider: rollout, priority: .custom(80))
/// ```
public final class RolloutProvider: FeatureFlagProvider, Sendable {
    public let name: String

    private let userId: String
    private let lock = OSAllocatedUnfairLock(initialState: State())

    private struct State: Sendable {
        /// Per-flag rollout percentages (0-100).
        var rollouts: [String: Int] = [:]
        /// Per-flag overrides for specific flag values (non-Bool).
        var rolloutValues: [String: FeatureFlagValue] = [:]
    }

    /// Initializes with a user identifier for deterministic hashing.
    /// - Parameters:
    ///   - userId: A stable identifier for the current user (e.g., user ID, device UUID).
    ///   - name: A display name for this provider.
    public init(userId: String, name: String = "Rollout") {
        self.userId = userId
        self.name = name
    }

    /// Sets the rollout percentage for a feature flag.
    /// Uses `feature.lookupKey` so grouped flags match service/resolver lookups.
    /// - Parameters:
    ///   - feature: The feature flag key.
    ///   - percentage: The percentage of users (0-100) who should have this flag enabled.
    ///   - value: The value to return when the user is in the rollout (defaults to `.bool(true)`).
    public func setRollout<F: FeatureFlagKey>(
        for feature: F,
        percentage: Int,
        value: FeatureFlagValue? = nil
    ) {
        let key = feature.lookupKey
        lock.withLock { state in
            state.rollouts[key] = max(0, min(100, percentage))
            if let value {
                state.rolloutValues[key] = value
            } else {
                state.rolloutValues.removeValue(forKey: key)
            }
        }
    }

    /// Removes the rollout configuration for a feature flag.
    public func removeRollout<F: FeatureFlagKey>(for feature: F) {
        let key = feature.lookupKey
        lock.withLock { state in
            state.rollouts.removeValue(forKey: key)
            state.rolloutValues.removeValue(forKey: key)
        }
    }

    /// Returns the current rollout percentage for a flag, if set.
    public func rolloutPercentage(for key: String) -> Int? {
        lock.withLock { state in
            state.rollouts[key]
        }
    }

    public func value(for key: String) -> FeatureFlagValue? {
        let (percentage, customValue): (Int?, FeatureFlagValue?) = lock.withLock { state in
            (state.rollouts[key], state.rolloutValues[key])
        }

        guard let percentage else { return nil }

        // 100% rollout: always enabled
        if percentage >= 100 {
            return customValue ?? .bool(true)
        }

        // 0% rollout: always disabled (do not fall through to lower providers)
        if percentage <= 0 {
            return customValue ?? .bool(false)
        }

        // Deterministic hash-based rollout
        if isInRollout(key: key, percentage: percentage) {
            return customValue ?? .bool(true)
        }

        return .bool(false)
    }

    /// Determines if the user is within the rollout percentage using a stable FNV-1a hash.
    private func isInRollout(key: String, percentage: Int) -> Bool {
        let hashInput = "\(userId):\(key)"
        let bucket = Int(StableHash.fnv1a64(hashInput) % 100)
        return bucket < percentage
    }
}

/// Stable, process-independent hashing for rollout bucketing.
enum StableHash {
    /// FNV-1a 64-bit over UTF-8 bytes.
    static func fnv1a64(_ string: String) -> UInt64 {
        let offsetBasis: UInt64 = 14695981039346656037
        let prime: UInt64 = 1099511628211
        var hash = offsetBasis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
