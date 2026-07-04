import Foundation

/// A provider that enables percentage-based feature flag rollouts.
///
/// Uses a deterministic hash of a user identifier to decide whether a feature
/// is enabled for a given user. This ensures the same user consistently gets
/// the same result for a given rollout percentage.
///
/// Example:
/// ```swift
/// let rollout = RolloutProvider(userId: "user-123")
/// rollout.setRollout(for: "new_feature", percentage: 50) // 50% rollout
/// service.register(provider: rollout, priority: .custom(80))
/// ```
public final class RolloutProvider: FeatureFlagProvider, @unchecked Sendable {
    public let name: String = "Rollout"
    
    private let userId: String
    private let lock = NSLock()
    
    /// Per-flag rollout percentages (0-100).
    private var rollouts: [String: Int] = [:]
    
    /// Per-flag overrides for specific flag values (non-Bool).
    private var rolloutValues: [String: Any] = [:]
    
    /// Initializes with a user identifier for deterministic hashing.
    /// - Parameters:
    ///   - userId: A stable identifier for the current user (e.g., user ID, device UUID).
    ///   - name: A display name for this provider.
    public init(userId: String, name: String = "Rollout") {
        self.userId = userId
    }
    
    /// Sets the rollout percentage for a feature flag.
    /// - Parameters:
    ///   - feature: The feature flag key.
    ///   - percentage: The percentage of users (0-100) who should have this flag enabled.
    ///   - value: The value to return when the user is in the rollout (defaults to `true` for Bool flags).
    public func setRollout<F: FeatureFlagKey>(for feature: F, percentage: Int, value: Any? = nil) {
        lock.withLock {
            rollouts[feature.rawValue] = max(0, min(100, percentage))
            if let value = value {
                rolloutValues[feature.rawValue] = value
            }
        }
    }
    
    /// Removes the rollout configuration for a feature flag.
    public func removeRollout<F: FeatureFlagKey>(for feature: F) {
        lock.withLock {
            rollouts.removeValue(forKey: feature.rawValue)
            rolloutValues.removeValue(forKey: feature.rawValue)
        }
    }
    
    /// Returns the current rollout percentage for a flag, if set.
    public func rolloutPercentage(for key: String) -> Int? {
        lock.withLock { rollouts[key] }
    }
    
    public func value(for key: String) -> Any? {
        var percentage: Int?
        var customValue: Any?
        lock.withLock {
            percentage = rollouts[key]
            customValue = rolloutValues[key]
        }
        
        guard let percentage = percentage else { return nil }
        
        // 100% rollout: always enabled
        if percentage >= 100 {
            return customValue ?? true
        }
        
        // 0% rollout: always disabled
        if percentage <= 0 {
            return nil
        }
        
        // Deterministic hash-based rollout
        if isInRollout(key: key, percentage: percentage) {
            return customValue ?? true
        }
        
        return nil
    }
    
    /// Determines if the user is within the rollout percentage using a deterministic hash.
    private func isInRollout(key: String, percentage: Int) -> Bool {
        let hashInput = "\(userId):\(key)"
        let hash = abs(hashInput.hashValue) % 100
        return hash < percentage
    }
}
