import Foundation

/// A simple provider backed by an in-memory dictionary.
/// Useful for setting up initial values or local configuration.
public struct LocalProvider: FeatureFlagProvider {
    public let name: String = "Local"
    private let flags: [String: any Sendable]
    
    /// Initializes with a dictionary of key-value pairs.
    public init(flags: [String: any Sendable]) {
        self.flags = flags
    }
    
    /// Initializes with a list of enabled keys (Sets them to true).
    /// All others are considered nil.
    public init(enabledFeatures: [any FeatureFlagKey]) {
        var dict: [String: any Sendable] = [:]
        for feature in enabledFeatures {
            dict[feature.rawValue] = true
        }
        self.flags = dict
    }
    
    public func value(for key: String) -> Any? {
        return flags[key]
    }
}
