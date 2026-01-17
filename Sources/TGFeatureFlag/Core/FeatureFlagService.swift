import Foundation
import Observation

/// The central manager for Feature Flags.
///
/// This service aggregates values from multiple `FeatureFlagProvider` sources.
/// It uses the `Observation` framework (@Observable) to automatically update SwiftUI views.
@Observable
public final class FeatureFlagService {
    
    /// The list of registered providers, ordered by priority (First has highest priority).
    private var providers: [any FeatureFlagProvider] = []
    
    /// A version counter to force UI updates when external sources (like UserDefaults) change.
    private var _updateTrigger: Int = 0
    
    public init() {
        // Observe UserDefaults changes to trigger updates for UserDefaultsProvider
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.triggerUpdate()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Registers a new provider.
    /// - Parameter provider: The provider to add.
    /// - Parameter priority: Defines where the provider is inserted in the chain.
    public enum Priority {
        case highest
        case lowest
    }
    
    public func register(provider: any FeatureFlagProvider, priority: Priority = .lowest) {
        switch priority {
        case .highest:
            providers.insert(provider, at: 0)
        case .lowest:
            providers.append(provider)
        }
    }
    
    /// Checks if a feature is enabled (Boolean only).
    public func isEnabled<F: FeatureFlagKey>(_ feature: F) -> Bool {
        value(for: feature)
    }
    
    /// Retrieves a typed value for a feature flag.
    /// Supports Bool, String, Int, Double.
    public func value<T, F: FeatureFlagKey>(for feature: F) -> T {
        // Access _updateTrigger to register dependency for Observation
        _ = _updateTrigger
        
        // 1. Check providers in order
        for provider in providers {
            if let rawValue = provider.value(for: feature.rawValue) {
                // Attempt to cast
                if let typedValue = rawValue as? T {
                    return typedValue
                }
            }
        }
        
        // 2. Fallback to default
        if let defaultTyped = feature.defaultValue as? T {
            return defaultTyped
        }
        
        // 3. Crash safety: If T matches the default value type, this shouldn't happen.
        // If the user requests a String but the default is Bool, we have a problem.
        // We return a reasonable default or crash in debug.
        fatalError("Feature Flag Type Mismatch: Expected \(T.self) for \(feature.rawValue), but default value was \(type(of: feature.defaultValue))")
    }
    
    /// Manually triggers an update notification.
    public func triggerUpdate() {
        _updateTrigger += 1
    }
    
    /// Helper to find a specific provider type.
    public func provider<T>(ofType type: T.Type) -> T? {
        providers.first { $0 is T } as? T
    }
}
