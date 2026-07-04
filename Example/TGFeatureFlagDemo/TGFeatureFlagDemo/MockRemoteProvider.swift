import Foundation
import TGFeatureFlag

/// A mock provider simulating a remote configuration service (e.g. Firebase Remote Config).
/// It allows simulating network fetches and updating feature flag values dynamically.
///
/// Implements `AsyncFeatureFlagProvider` for async refresh via `FeatureFlagService.refresh()`.
public final class MockRemoteProvider: AsyncFeatureFlagProvider, @unchecked Sendable {
    public let name: String = "Remote Config"
    
    // Thread-safe storage for fetched flags
    private var flags: [String: Any] = [:]
    private let queue = DispatchQueue(label: "com.demo.mockremote", attributes: .concurrent)
    
    public init() {}
    
    public func value(for key: String) -> Any? {
        queue.sync {
            flags[key]
        }
    }
    
    /// Async fetch implementation for `FeatureFlagService.refresh()`.
    public func fetchValues() async throws {
        // Simulate network delay
        try await Task.sleep(for: .seconds(1.5))
        
        // Simulated remote values
        let newConfig: [String: Any] = [
            "feature_new_home": true,
            "feature_social_tab": true,
            "config_api_base_url": "https://api.staging.remote.com",
            "feature_detailed_navigation": true
        ]
        
        queue.async(flags: .barrier) {
            self.flags = newConfig
        }
    }
    
    /// Legacy callback-based fetch for backward compatibility.
    /// - Parameter completion: Called when the fetch is complete.
    public func fetchRemoteConfig(completion: @escaping () -> Void) {
        Task {
            try? await fetchValues()
            await MainActor.run { completion() }
        }
    }
}
