import Foundation
import TGFeatureFlag

/// A mock provider simulating a remote configuration service (e.g. Firebase Remote Config).
/// It allows simulating network fetches and updating feature flag values dynamically.
public final class MockRemoteProvider: FeatureFlagProvider, @unchecked Sendable {
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
    
    /// Simulates fetching configuration from a remote server.
    /// - Parameters:
    ///   - completion: Called when the fetch is complete.
    public func fetchRemoteConfig(completion: @escaping () -> Void) {
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            
            // Simulated remote values
            let newConfig: [String: Any] = [
                // Disable new home design remotely (overrides local default 'true')
                "feature_new_home": true,
                
                // Enable social tab remotely (overrides local default 'false')
                "feature_social_tab": true,
                
                // Change API URL remotely
                "config_api_base_url": "https://api.staging.remote.com",
                
                // Keep detailed navigation enabled
                "feature_detailed_navigation": true
            ]
            
            self.queue.async(flags: .barrier) {
                self.flags = newConfig
                
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }
}
