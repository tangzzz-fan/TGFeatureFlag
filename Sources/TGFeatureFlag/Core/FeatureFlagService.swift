import Foundation
import Observation

/// Protocol for logging feature flag resolution events.
///
/// Implement this to observe which provider resolved each flag, useful for debugging in production.
///
/// Example:
/// ```swift
/// class PrintLogger: FeatureFlagLogger {
///     func log(flag: String, resolvedBy provider: String?, value: Any?) {
///         print("[Flag] \(flag) = \(value ?? "nil") (from: \(provider ?? "default"))")
///     }
/// }
/// ```
public protocol FeatureFlagLogger: Sendable {
    /// Called when a feature flag value is resolved.
    /// - Parameters:
    ///   - flag: The raw key of the feature flag.
    ///   - provider: The name of the provider that resolved it, or `nil` if using default.
    ///   - value: The resolved value, or `nil` if falling back to default.
    func log(flag: String, resolvedBy provider: String?, value: Any?)
}

/// The central manager for Feature Flags.
///
/// This service aggregates values from multiple `FeatureFlagProvider` sources.
/// It uses the `Observation` framework (@Observable) to automatically update SwiftUI views.
@MainActor
@Observable
public final class FeatureFlagService {
    
    /// Internal storage: providers sorted by priority (highest first).
    private struct ProviderEntry {
        let priority: Int
        let provider: any FeatureFlagProvider
    }
    
    /// The list of registered providers, ordered by priority (First has highest priority).
    private var providerEntries: [ProviderEntry] = []
    
    /// Computed list of providers for backward compatibility.
    private var providers: [any FeatureFlagProvider] {
        providerEntries.map(\.provider)
    }
    
    /// Optional logger for observing flag resolution.
    private var logger: (any FeatureFlagLogger)?
    
    /// A version counter to force UI updates when external sources (like UserDefaults) change.
    private var _updateTrigger: Int = 0
    
    public init() {
        // Observe UserDefaults changes to trigger updates for UserDefaultsProvider
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
    
    /// Defines where a provider is inserted in the resolution chain.
    ///
    /// - `highest`: Inserted at the front (priority = Int.max).
    /// - `lowest`: Inserted at the end (priority = Int.min).
    /// - `custom(Int)`: Inserted at a specific priority level. Higher values = higher priority.
    public enum Priority {
        case highest
        case lowest
        case custom(Int)
        
        var rawValue: Int {
            switch self {
            case .highest: return Int.max
            case .lowest: return Int.min
            case .custom(let value): return value
            }
        }
    }
    
    /// Registers a new provider with a given priority.
    /// - Parameters:
    ///   - provider: The provider to add.
    ///   - priority: Defines where the provider is inserted in the chain.
    public func register(provider: any FeatureFlagProvider, priority: Priority = .lowest) {
        let entry = ProviderEntry(priority: priority.rawValue, provider: provider)
        // Insert in sorted position (descending by priority)
        if let index = providerEntries.firstIndex(where: { entry.priority > $0.priority }) {
            providerEntries.insert(entry, at: index)
        } else {
            providerEntries.append(entry)
        }
    }
    
    /// Sets a logger to observe all flag resolution events.
    /// - Parameter logger: The logger to use, or `nil` to disable logging.
    public func setLogger(_ logger: (any FeatureFlagLogger)?) {
        self.logger = logger
    }
    
    /// Checks if a feature is enabled (Boolean only).
    public func isEnabled<F: FeatureFlagKey>(_ feature: F) -> Bool {
        value(for: feature)
    }
    
    /// Resolves the lookup key for a feature flag.
    /// Uses the qualified key (with group prefix) for grouped flags, otherwise the raw value.
    private func _resolveKey<F: FeatureFlagKey>(for feature: F) -> String {
        if let grouped = feature as? any GroupedFeatureFlag {
            return grouped.qualifiedKey
        }
        return feature.rawValue
    }
    
    /// Retrieves a typed value for a feature flag.
    /// Supports Bool, String, Int, Double.
    public func value<T, F: FeatureFlagKey>(for feature: F) -> T {
        // Access _updateTrigger to register dependency for Observation
        _ = _updateTrigger
        
        let lookupKey = _resolveKey(for: feature)
        
        // 1. Check providers in priority order
        for entry in providerEntries {
            let provider = entry.provider
            // Fault-tolerant: guard against provider errors
            let rawValue: Any?
            do {
                rawValue = try _safeValue(from: provider, for: lookupKey)
            } catch {
                logger?.log(flag: lookupKey, resolvedBy: nil, value: nil)
                continue
            }
            
            if let rawValue = rawValue {
                // Attempt to cast
                if let typedValue = rawValue as? T {
                    logger?.log(flag: lookupKey, resolvedBy: provider.name, value: typedValue)
                    return typedValue
                }
            }
        }
        
        // 2. Fallback to default
        if let defaultTyped = feature.defaultValue as? T {
            logger?.log(flag: lookupKey, resolvedBy: nil, value: defaultTyped)
            return defaultTyped
        }
        
        // 3. Crash safety: If T matches the default value type, this shouldn't happen.
        // If the user requests a String but the default is Bool, we have a problem.
        // We return a reasonable default or crash in debug.
        fatalError("Feature Flag Type Mismatch: Expected \(T.self) for \(lookupKey), but default value was \(type(of: feature.defaultValue))")
    }
    
    /// Safely retrieves a value from a provider, catching any errors.
    private func _safeValue(from provider: any FeatureFlagProvider, for key: String) throws -> Any? {
        return provider.value(for: key)
    }
    
    /// Manually triggers an update notification.
    public func triggerUpdate() {
        _updateTrigger += 1
    }
    
    /// Refreshes all registered `AsyncFeatureFlagProvider` instances by calling their `fetchValues()` method.
    ///
    /// After all async providers have fetched their latest values, the service triggers a UI update.
    /// Errors from individual providers are caught and logged but do not prevent other providers from refreshing.
    ///
    /// - Returns: The number of providers that failed to refresh.
    @discardableResult
    public func refresh() async -> Int {
        var failureCount = 0
        
        for entry in providerEntries {
            guard let asyncProvider = entry.provider as? any AsyncFeatureFlagProvider else {
                continue
            }
            do {
                try await asyncProvider.fetchValues()
                logger?.log(flag: "*", resolvedBy: asyncProvider.name, value: "refreshed")
            } catch {
                failureCount += 1
                logger?.log(flag: "*", resolvedBy: asyncProvider.name, value: "refresh_failed: \(error)")
            }
        }
        
        triggerUpdate()
        return failureCount
    }
    
    /// Helper to find a specific provider type.
    public func provider<T>(ofType type: T.Type) -> T? {
        providers.first { $0 is T } as? T
    }
}
