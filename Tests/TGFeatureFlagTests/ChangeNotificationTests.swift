import Testing
import Foundation
import Observation
import os
@testable import TGFeatureFlagCore

@Suite("Change notification")
struct ChangeNotificationTests {

    @MainActor
    @Test("Changing a rollout percentage updates the service without a manual trigger")
    func rolloutChangePropagates() async {
        let service = FeatureFlagService()
        let rollout = RolloutProvider(userId: "change-user")
        rollout.setRollout(for: BoolTestFeature.booleanFeature, percentage: 0)
        service.register(provider: rollout, priority: .highest)

        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == false)

        let invalidated = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = service.value(for: BoolTestFeature.booleanFeature)
        } onChange: {
            invalidated.withLock { $0 = true }
        }

        rollout.setRollout(for: BoolTestFeature.booleanFeature, percentage: 100)

        #expect(await waitUntil { invalidated.withLock { $0 } })
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == true)
    }

    @MainActor
    @Test("A debug override updates the service without a manual trigger")
    func debugOverridePropagates() async {
        let service = FeatureFlagService()
        let debug = DebugProvider()
        service.register(provider: debug, priority: .highest)

        let invalidated = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = service.value(for: BoolTestFeature.booleanFeature)
        } onChange: {
            invalidated.withLock { $0 = true }
        }

        debug.setOverride(for: BoolTestFeature.booleanFeature, value: .bool(true))

        #expect(await waitUntil { invalidated.withLock { $0 } })
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == true)

        debug.reset()
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == false)
    }

    @MainActor
    @Test("Changing the rollout identity re-buckets the user")
    func identityChangeRebuckets() async {
        let key = BoolTestFeature.booleanFeature.lookupKey
        func bucket(_ userId: String) -> Int {
            Int(StableHash.fnv1a64("\(userId):\(key)") % 100)
        }

        let service = FeatureFlagService()
        let rollout = RolloutProvider(userId: "identity-a")
        rollout.setRollout(for: BoolTestFeature.booleanFeature, percentage: 50)
        service.register(provider: rollout, priority: .highest)

        let original = service.isEnabled(BoolTestFeature.booleanFeature)
        #expect(original == (bucket("identity-a") < 50))

        // Pick an identity that lands on the other side of the 50% split.
        guard let other = (0..<500).map({ "identity-\($0)" }).first(where: { (bucket($0) < 50) != original }) else {
            Issue.record("could not find an identity on the opposite side of the split")
            return
        }

        let invalidated = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = service.value(for: BoolTestFeature.booleanFeature)
        } onChange: {
            invalidated.withLock { $0 = true }
        }

        rollout.userId = other

        #expect(await waitUntil { invalidated.withLock { $0 } })
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == !original)
    }

    @MainActor
    @Test("Redux mode can observe provider changes without the service")
    func resolverChangeHandler() async {
        let resolver = FeatureFlagResolver()
        let rollout = RolloutProvider(userId: "resolver-user")
        rollout.setRollout(for: BoolTestFeature.booleanFeature, percentage: 0)
        resolver.register(provider: rollout, priority: .highest)

        let changes = OSAllocatedUnfairLock(initialState: 0)
        resolver.setChangeHandler {
            changes.withLock { $0 += 1 }
        }

        rollout.setRollout(for: BoolTestFeature.booleanFeature, percentage: 100)

        #expect(await waitUntil { changes.withLock { $0 } == 1 })
        #expect(resolver.isEnabled(BoolTestFeature.booleanFeature) == true)
    }

    @Test("Broadcaster notifies every observer and stops after release")
    func broadcasterFanOut() {
        let broadcaster = FeatureFlagChangeBroadcaster()
        let first = OSAllocatedUnfairLock(initialState: 0)
        let second = OSAllocatedUnfairLock(initialState: 0)

        var firstObservation: FeatureFlagChangeObservation? = broadcaster.observe {
            first.withLock { $0 += 1 }
        }
        let secondObservation = broadcaster.observe {
            second.withLock { $0 += 1 }
        }

        broadcaster.notify()
        #expect(first.withLock { $0 } == 1)
        #expect(second.withLock { $0 } == 1)

        firstObservation = nil
        #expect(firstObservation == nil)

        broadcaster.notify()
        #expect(first.withLock { $0 } == 1, "a released observation must stop receiving")
        #expect(second.withLock { $0 } == 2)

        withExtendedLifetime(secondObservation) {}
    }

    @MainActor
    @Test("Reset on an untouched provider does not invalidate observers")
    func resetWithoutOverridesIsQuiet() async {
        let service = FeatureFlagService()
        let debug = DebugProvider()
        service.register(provider: debug, priority: .highest)

        let invalidated = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = service.value(for: BoolTestFeature.booleanFeature)
        } onChange: {
            invalidated.withLock { $0 = true }
        }

        debug.reset()

        // Give any spurious task a chance to run before asserting the negative.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(invalidated.withLock { $0 } == false)
    }
}
