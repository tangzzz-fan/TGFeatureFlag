import Foundation

/// Protocol for feature flag providers that fetch values asynchronously (e.g., remote config services).
///
/// Async providers cache values locally after a fetch. The synchronous `value(for:)` method
/// returns cached values, while `fetchValues()` performs the actual async fetch operation.
///
/// Use `FeatureFlagService.refresh()` to trigger a fetch across all registered async providers.
///
/// Example:
/// ```swift
/// class FirebaseProvider: AsyncFeatureFlagProvider, @unchecked Sendable {
///     let name = "Firebase"
///     private var cache: [String: Any] = [:]
///
///     func value(for key: String) -> Any? { cache[key] }
///
///     func fetchValues() async throws {
///         let config = try await RemoteConfig.remoteConfig().fetchAndActivate()
///         cache = config.allKeys.reduce(into: [:]) { $0[$1] = config[$1].stringValue }
///     }
/// }
/// ```
public protocol AsyncFeatureFlagProvider: FeatureFlagProvider {
    /// Fetches the latest values from the remote source.
    ///
    /// This method is called by `FeatureFlagService.refresh()`.
    /// Implementations should update their internal cache so that subsequent
    /// calls to `value(for:)` return the new values.
    func fetchValues() async throws
}
