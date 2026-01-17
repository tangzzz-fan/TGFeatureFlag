import Foundation
import Combine

/// A provider that reads feature flags from UserDefaults.
/// This is commonly used to integrate with the iOS Settings.bundle or for simple persistence.
///
/// It observes `UserDefaults.didChangeNotification` to automatically notify the service of changes.
public final class UserDefaultsProvider: FeatureFlagProvider, @unchecked Sendable {
    public let name: String
    private let userDefaults: UserDefaults
    
    /// Initializes the provider.
    /// - Parameters:
    ///   - userDefaults: The UserDefaults instance to read from. Defaults to `.standard`.
    ///   - name: A display name for this provider. Defaults to "UserDefaults".
    public init(userDefaults: UserDefaults = .standard, name: String = "UserDefaults") {
        self.userDefaults = userDefaults
        self.name = name
    }
    
    public func value(for key: String) -> Any? {
        // UserDefaults returns nil if the key doesn't exist, which is what we want.
        // It handles String, Int, Bool automatically.
        return userDefaults.object(forKey: key)
    }
}
