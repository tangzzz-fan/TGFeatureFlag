import Testing
import Foundation
import Observation
import os
@testable import TGFeatureFlagCore

enum RemoteFeature: String, TypedFeatureFlag {
    case v2Flow = "checkout.v2_flow"
    var typedDefaultValue: Bool { false }
}

/// Configuration keys, addressed directly: they are only read through the provider's
/// string-keyed API, so they need no typed key.
private enum ConfigKey {
    static let bannerText = "config_banner_text"
    static let retryCount = "config_retry_count"
    static let ratio = "config_ratio"
}

@MainActor
@Suite("Remote rollout")
struct RemoteRolloutTests {

    private func provider(_ userId: String = "remote-user") -> RemoteRolloutProvider {
        RemoteRolloutProvider(userId: userId)
    }

    @Test("A payload with bare literals configures every value type")
    func bareLiteralPayload() throws {
        let remote = provider()
        let json = """
        {
          "rollouts": {
            "checkout.v2_flow": { "percentage": 100 },
            "config_banner_text": { "percentage": 100, "value": "Try the new checkout" },
            "config_retry_count": { "percentage": 100, "value": 5 },
            "config_ratio": { "percentage": 100, "value": 1.5 }
          }
        }
        """

        try remote.apply(json: Data(json.utf8))

        #expect(remote.value(for: RemoteFeature.v2Flow.lookupKey) == .bool(true))
        #expect(remote.value(for: ConfigKey.bannerText) == .string("Try the new checkout"))
        #expect(remote.value(for: ConfigKey.retryCount) == .int(5))
        #expect(remote.value(for: ConfigKey.ratio) == .double(1.5))
        #expect(remote.ignoredKeys.isEmpty)
    }

    @Test("Tagged values are also accepted, so a payload may round-trip")
    func taggedPayload() throws {
        let remote = provider()
        let json = """
        { "rollouts": { "config_retry_count": { "percentage": 100, "value": { "type": "int", "value": 7 } } } }
        """

        try remote.apply(json: Data(json.utf8))

        #expect(remote.value(for: ConfigKey.retryCount) == .int(7))
    }

    @Test("0% is off and does not fall through; 100% is on")
    func extremes() throws {
        let service = FeatureFlagService()
        let remote = provider()
        try remote.apply(json: Data("""
        { "rollouts": { "checkout.v2_flow": { "percentage": 0 } } }
        """.utf8))

        service.register(provider: remote, priority: .highest)
        service.register(
            provider: LocalProvider(flags: [RemoteFeature.v2Flow.lookupKey: .bool(true)]),
            priority: .lowest
        )

        // 0% must block the lower provider rather than letting it win.
        #expect(service.isEnabled(RemoteFeature.v2Flow) == false)

        try remote.apply(json: Data("""
        { "rollouts": { "checkout.v2_flow": { "percentage": 100 } } }
        """.utf8))
        #expect(service.isEnabled(RemoteFeature.v2Flow) == true)
    }

    @Test("A partial rollout matches the stable bucket for the identity")
    func partialRolloutUsesStableBucket() throws {
        let userId = "bucket-user"
        let key = RemoteFeature.v2Flow.lookupKey
        let expectedBucket = Int(StableHash.fnv1a64("\(userId):\(key)") % 100)

        let remote = provider(userId)
        try remote.apply(json: Data("""
        { "rollouts": { "\(key)": { "percentage": 50 } } }
        """.utf8))

        #expect(remote.value(for: key) == .bool(expectedBucket < 50))
    }

    @Test("Bucketing is stable across provider instances")
    func stableAcrossInstances() throws {
        let payload = Data("""
        { "rollouts": { "checkout.v2_flow": { "percentage": 37 } } }
        """.utf8)

        let first = provider("stable-user")
        let second = provider("stable-user")
        try first.apply(json: payload)
        try second.apply(json: payload)

        #expect(first.value(for: RemoteFeature.v2Flow.lookupKey) == second.value(for: RemoteFeature.v2Flow.lookupKey))
    }

    @Test("Malformed entries are skipped and reported, the rest still apply")
    func malformedEntriesAreSkipped() throws {
        let remote = provider()
        let json = """
        {
          "rollouts": {
            "checkout.v2_flow": { "percentage": 100 },
            "config_retry_count": { "value": 5 },
            "config_ratio": { "percentage": 100, "value": { "type": "json", "value": {} } }
          }
        }
        """

        try remote.apply(json: Data(json.utf8))

        #expect(remote.value(for: RemoteFeature.v2Flow.lookupKey) == .bool(true))
        #expect(remote.value(for: ConfigKey.retryCount) == nil)
        #expect(remote.value(for: ConfigKey.ratio) == nil)
        #expect(remote.ignoredKeys == ["config_ratio", "config_retry_count"])
    }

    @Test("A structurally invalid payload throws and leaves the previous config intact")
    func invalidPayloadKeepsPreviousConfig() throws {
        let remote = provider()
        try remote.apply(json: Data("""
        { "rollouts": { "checkout.v2_flow": { "percentage": 100 } } }
        """.utf8))

        #expect(throws: (any Error).self) {
            try remote.apply(json: Data("[1, 2, 3]".utf8))
        }

        #expect(remote.value(for: RemoteFeature.v2Flow.lookupKey) == .bool(true))
    }

    @Test("Applying a payload drops flags that are no longer listed")
    func applyReplacesTheWholeSet() throws {
        let remote = provider()
        try remote.apply(json: Data("""
        { "rollouts": { "checkout.v2_flow": { "percentage": 100 } } }
        """.utf8))
        #expect(remote.value(for: RemoteFeature.v2Flow.lookupKey) == .bool(true))

        try remote.apply(json: Data("""
        { "rollouts": { "config_banner_text": { "percentage": 100, "value": "hi" } } }
        """.utf8))

        // The flag left the document, so it must stop rolling out rather than keep 100%.
        #expect(remote.value(for: RemoteFeature.v2Flow.lookupKey) == nil)
    }

    @Test("Clearing falls back to lower providers")
    func clearFallsThrough() throws {
        let service = FeatureFlagService()
        let remote = provider()
        try remote.apply(json: Data("""
        { "rollouts": { "checkout.v2_flow": { "percentage": 100 } } }
        """.utf8))

        service.register(provider: remote, priority: .highest)
        service.register(
            provider: LocalProvider(flags: [RemoteFeature.v2Flow.lookupKey: .bool(false)]),
            priority: .lowest
        )
        #expect(service.isEnabled(RemoteFeature.v2Flow) == true)

        remote.clear()
        #expect(service.isEnabled(RemoteFeature.v2Flow) == false)
    }

    @MainActor
    @Test("Changing the percentage at runtime reaches the UI without a restart")
    func percentageChangeReachesUI() async throws {
        let service = FeatureFlagService()
        let remote = provider()
        try remote.apply(json: Data("""
        { "rollouts": { "checkout.v2_flow": { "percentage": 0 } } }
        """.utf8))
        service.register(provider: remote, priority: .highest)

        #expect(service.isEnabled(RemoteFeature.v2Flow) == false)

        let invalidated = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = service.value(for: RemoteFeature.v2Flow)
        } onChange: {
            invalidated.withLock { $0 = true }
        }

        // What an operator rolling out from 0% to 100% would push.
        try remote.apply(json: Data("""
        { "rollouts": { "checkout.v2_flow": { "percentage": 100 } } }
        """.utf8))

        #expect(await waitUntil { invalidated.withLock { $0 } })
        #expect(service.isEnabled(RemoteFeature.v2Flow) == true)
    }

    @Test("Changing the identity re-buckets")
    func identityChangeRebuckets() throws {
        let key = RemoteFeature.v2Flow.lookupKey
        func bucket(_ userId: String) -> Int {
            Int(StableHash.fnv1a64("\(userId):\(key)") % 100)
        }

        let remote = provider("remote-a")
        try remote.apply(json: Data("""
        { "rollouts": { "\(key)": { "percentage": 50 } } }
        """.utf8))

        let original = remote.value(for: key)
        guard let other = (0..<500).map({ "remote-\($0)" }).first(where: { (bucket($0) < 50) != (original == .bool(true)) }) else {
            Issue.record("could not find an identity on the opposite side of the split")
            return
        }

        remote.userId = other
        #expect(remote.value(for: key) != original)
    }
}
