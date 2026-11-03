import Foundation
import os
import TGFeatureFlag

/// A mock remote configuration service, standing in for Firebase Remote Config or an
/// in-house config endpoint.
///
/// The delay is deliberate: it makes the difference between a cold start that renders
/// defaults and one primed from the last-known-good cache visible.
final class MockRemoteProvider: AsyncFeatureFlagProvider, Sendable {
    let name = "Remote Config"

    private let lock = OSAllocatedUnfairLock(initialState: [String: FeatureFlagValue]())

    func value(for key: String) -> FeatureFlagValue? {
        lock.withLock { $0[key] }
    }

    func fetchValues() async throws {
        try await Task.sleep(for: .milliseconds(1500))

        let config: [String: FeatureFlagValue] = [
            DemoFeature.newHomeDesign.lookupKey: .bool(true),
            DemoFeature.socialTab.lookupKey: .bool(true),
            DemoConfig.apiBaseURL.lookupKey: .string("https://api.staging.remote.example"),
            DemoConfig.welcomeMessage.lookupKey: .string(
                "Remote config is active — these strings came from the mock backend."
            )
        ]

        lock.withLock { $0 = config }
    }
}

/// A provider that always fails, so the refresh report and the `refreshFailed` event have
/// something to show.
///
/// Every real app has one of these: an endpoint that is down, a token that expired, a
/// service the app can live without. The point is that it fails on its own without taking
/// the other providers down with it.
struct FlakyProvider: AsyncFeatureFlagProvider {
    struct Offline: Error, CustomStringConvertible {
        var description: String { "endpoint offline" }
    }

    let name = "Flaky Endpoint"

    /// Never contributes a value; it exists to fail during refresh.
    func value(for key: String) -> FeatureFlagValue? { nil }

    func fetchValues() async throws {
        try await Task.sleep(for: .milliseconds(300))
        throw Offline()
    }
}
