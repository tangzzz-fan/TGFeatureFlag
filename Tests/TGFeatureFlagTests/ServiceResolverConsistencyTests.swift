import Testing
import Foundation
import Observation
import os
@testable import TGFeatureFlagCore

@MainActor
@Suite("Service and resolver consistency")
struct ServiceResolverConsistencyTests {

    /// Registers the same provider instances into both modes, so any divergence in
    /// resolution, ordering, logging or override handling shows up as a mismatch.
    private func makeChain() -> (FeatureFlagService, FeatureFlagResolver) {
        let debug = DebugProvider()
        let rollout = RolloutProvider(userId: "consistency-user")
        rollout.setRollout(for: GroupedTestFeature.featureA, percentage: 100)
        let local = LocalProvider(flags: [
            BoolTestFeature.booleanFeature.lookupKey: .bool(true),
            StringTestFeature.stringFeature.lookupKey: .string("local"),
            IntTestFeature.intFeature.lookupKey: .int(9),
            GroupedTestFeature.featureB.lookupKey: .bool(true)
        ])

        let service = FeatureFlagService()
        let resolver = FeatureFlagResolver()

        let chain: [(any FeatureFlagProvider, FeatureFlagPriority)] = [
            (debug, .highest),
            (rollout, .custom(80)),
            (local, .lowest)
        ]
        for (provider, priority) in chain {
            service.register(provider: provider, priority: priority)
            resolver.register(provider: provider, priority: priority)
        }

        return (service, resolver)
    }

    @Test("Both modes resolve every key identically")
    func identicalResolution() {
        let (service, resolver) = makeChain()

        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == resolver.isEnabled(BoolTestFeature.booleanFeature))
        #expect(service.value(for: StringTestFeature.stringFeature) == resolver.value(for: StringTestFeature.stringFeature))
        #expect(service.value(for: IntTestFeature.intFeature) == resolver.value(for: IntTestFeature.intFeature))

        #expect(service.isEnabled(GroupedTestFeature.featureA) == resolver.isEnabled(GroupedTestFeature.featureA))
        #expect(service.isEnabled(GroupedTestFeature.featureB) == resolver.isEnabled(GroupedTestFeature.featureB))
    }

    @Test("Both modes build identical snapshots")
    func identicalSnapshot() {
        let (service, resolver) = makeChain()

        #expect(
            service.snapshot(for: [BoolTestFeature.booleanFeature])
                == resolver.snapshot(for: [BoolTestFeature.booleanFeature])
        )
        #expect(
            service.snapshot(for: [StringTestFeature.stringFeature])
                == resolver.snapshot(for: [StringTestFeature.stringFeature])
        )
        #expect(
            service.snapshot(for: [IntTestFeature.intFeature])
                == resolver.snapshot(for: [IntTestFeature.intFeature])
        )
    }

    @Test("Typed accessors agree with the resolver")
    func typedAccessorsAgree() {
        let (service, resolver) = makeChain()

        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == resolver.isEnabled(BoolTestFeature.booleanFeature))
        #expect(service.value(for: StringTestFeature.stringFeature) == "local")
        #expect(service.value(for: IntTestFeature.intFeature) == 9)
        #expect(service.value(for: IntTestFeature.intFeature) == resolver.value(for: IntTestFeature.intFeature))
    }

    @Test("Provider lookup returns the same instance in both modes")
    func providerLookupIsShared() {
        let (service, resolver) = makeChain()

        #expect(service.provider(ofType: DebugProvider.self) === resolver.provider(ofType: DebugProvider.self))
        #expect(service.provider(ofType: RolloutProvider.self) === resolver.provider(ofType: RolloutProvider.self))
        #expect(service.provider(ofType: UserDefaultsProvider.self) == nil)
    }

    @Test("A debug override is visible through both modes at once")
    func overrideIsShared() {
        let (service, resolver) = makeChain()

        let debug = service.provider(ofType: DebugProvider.self)
        debug?.setOverride(for: BoolTestFeature.booleanFeature, value: .bool(false))

        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == false)
        #expect(resolver.isEnabled(BoolTestFeature.booleanFeature) == false)
    }

    @Test("Registering a provider invalidates existing observers")
    func registerInvalidates() {
        let service = FeatureFlagService()
        let invalidated = OSAllocatedUnfairLock(initialState: false)

        withObservationTracking {
            _ = service.value(for: BoolTestFeature.booleanFeature)
        } onChange: {
            invalidated.withLock { $0 = true }
        }

        service.register(
            provider: LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(true)]),
            priority: .highest
        )

        #expect(invalidated.withLock { $0 })
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == true)
    }
}
