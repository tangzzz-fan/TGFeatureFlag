import Foundation

/// A mutable provider intended for debug builds.
/// Allows runtime toggling of feature flags to test different states.
public final class DebugProvider: FeatureFlagProvider, @unchecked Sendable {
    public let name: String = "Debug Override"
    
    // Thread-safe storage
    private let lock = NSLock()
    private var overrides: [String: Any] = [:]
    
    public init() {}
    
    public func value(for key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return overrides[key]
    }
    
    /// Overrides a feature flag value.
    public func setOverride<F: FeatureFlagKey>(for feature: F, value: Any?) {
        lock.lock()
        defer { lock.unlock() }
        if let value = value {
            overrides[feature.rawValue] = value
        } else {
            overrides.removeValue(forKey: feature.rawValue)
        }
    }
    
    /// Clears all overrides.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        overrides.removeAll()
    }
}
