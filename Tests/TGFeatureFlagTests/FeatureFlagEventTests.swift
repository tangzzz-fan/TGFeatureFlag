import Testing
import Foundation
@testable import TGFeatureFlagCore

@MainActor
@Suite("Feature flag events")
struct FeatureFlagEventTests {

    @Test("Reading the same flag repeatedly reports one exposure")
    func exposureIsDeduplicated() {
        let sink = TestEventSink()
        let resolver = FeatureFlagResolver()
        resolver.setEventSink(sink)
        resolver.register(
            provider: LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(true)]),
            priority: .highest
        )

        // A view body can read a flag on every frame; that must not look like many users.
        for _ in 0..<50 {
            _ = resolver.isEnabled(BoolTestFeature.booleanFeature)
        }

        #expect(sink.exposures.count == 1)
        #expect(sink.exposures.first?.flag == BoolTestFeature.booleanFeature.lookupKey)
        #expect(sink.exposures.first?.value == .bool(true))
    }

    @Test("A change of value reports a second exposure")
    func exposureTracksValue() {
        let sink = TestEventSink()
        let resolver = FeatureFlagResolver()
        resolver.setEventSink(sink)
        let debug = DebugProvider()
        resolver.register(provider: debug, priority: .highest)

        _ = resolver.isEnabled(BoolTestFeature.booleanFeature)
        debug.setOverride(for: BoolTestFeature.booleanFeature, value: .bool(true))
        _ = resolver.isEnabled(BoolTestFeature.booleanFeature)
        _ = resolver.isEnabled(BoolTestFeature.booleanFeature)

        #expect(sink.exposures.map(\.value) == [.bool(false), .bool(true)])
    }

    @Test("A new session reports the same exposure again")
    func newSessionResetsDeduplication() {
        let sink = TestEventSink()
        let resolver = FeatureFlagResolver()
        resolver.setEventSink(sink)
        resolver.register(
            provider: LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(true)]),
            priority: .highest
        )

        _ = resolver.isEnabled(BoolTestFeature.booleanFeature)
        #expect(sink.exposures.count == 1)

        resolver.startNewSession()
        _ = resolver.isEnabled(BoolTestFeature.booleanFeature)
        #expect(sink.exposures.count == 2)
    }

    @Test("Per-read resolution events are off unless asked for")
    func resolutionsAreOptIn() {
        let sink = TestEventSink()
        let resolver = FeatureFlagResolver()
        resolver.setEventSink(sink)   // .standard
        resolver.register(
            provider: LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(true)]),
            priority: .highest
        )

        _ = resolver.isEnabled(BoolTestFeature.booleanFeature)

        #expect(sink.resolutions.isEmpty)
        #expect(sink.exposures.count == 1)
    }

    @Test("A value of the wrong case reports a type mismatch instead of failing silently")
    func typeMismatchIsReported() {
        let sink = TestEventSink()
        let resolver = FeatureFlagResolver()
        resolver.setEventSink(sink)
        resolver.register(
            provider: LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .string("oops")]),
            priority: .highest
        )

        // The read still succeeds by falling back, but the mismatch is no longer invisible.
        #expect(resolver.value(for: BoolTestFeature.booleanFeature) == false)

        let mismatches = sink.events.compactMap { event -> (String, String, FeatureFlagValue)? in
            guard case .typeMismatch(let flag, let expected, let actual) = event else { return nil }
            return (flag, expected, actual)
        }
        #expect(mismatches.count == 1)
        #expect(mismatches.first?.0 == BoolTestFeature.booleanFeature.lookupKey)
        #expect(mismatches.first?.1 == "Bool")
        #expect(mismatches.first?.2 == .string("oops"))
    }

    @Test("Reading a misconfigured flag repeatedly reports one mismatch")
    func typeMismatchIsDeduplicated() {
        let sink = TestEventSink()
        let resolver = FeatureFlagResolver()
        resolver.setEventSink(sink)
        let debug = DebugProvider()
        resolver.register(provider: debug, priority: .highest)
        debug.setOverride(for: BoolTestFeature.booleanFeature, value: .string("oops"))

        func mismatchCount() -> Int {
            sink.events.filter { event in
                if case .typeMismatch = event { return true }
                return false
            }.count
        }

        // A misconfigured flag stays misconfigured; re-reporting it on every body evaluation
        // would flood the sink without adding information.
        for _ in 0..<50 {
            _ = resolver.isEnabled(BoolTestFeature.booleanFeature)
        }
        #expect(mismatchCount() == 1)

        // A different offending value is a different problem, so it reports again.
        debug.setOverride(for: BoolTestFeature.booleanFeature, value: .string("still oops"))
        _ = resolver.isEnabled(BoolTestFeature.booleanFeature)
        #expect(mismatchCount() == 2)
    }

    @Test("Refresh outcomes are typed events, not values smuggled through a flag field")
    func refreshEvents() async throws {
        let sink = TestEventSink()
        let resolver = FeatureFlagResolver()
        resolver.setEventSink(sink)
        resolver.register(provider: SlowProvider(name: "healthy", delay: .zero), priority: .highest)
        resolver.register(
            provider: SlowProvider(name: "broken", delay: .zero, shouldFail: true),
            priority: .custom(50)
        )
        resolver.register(provider: SlowProvider(name: "hanging", delay: .seconds(5)), priority: .lowest)

        _ = try await resolver.refresh(timeout: .milliseconds(100))

        let refreshed = sink.events.compactMap { event -> String? in
            guard case .refreshed(let provider, _) = event else { return nil }
            return provider
        }
        let failed = sink.events.compactMap { event -> String? in
            guard case .refreshFailed(let provider, _) = event else { return nil }
            return provider
        }
        let timedOut = sink.events.compactMap { event -> String? in
            guard case .refreshTimedOut(let provider) = event else { return nil }
            return provider
        }

        #expect(refreshed == ["healthy"])
        #expect(failed == ["broken"])
        #expect(timedOut == ["hanging"])
    }

    @Test("No sink means no work and no crash")
    func withoutSink() {
        let resolver = FeatureFlagResolver()
        resolver.register(
            provider: LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(true)]),
            priority: .highest
        )

        #expect(resolver.isEnabled(BoolTestFeature.booleanFeature))
        resolver.startNewSession()
    }
}
