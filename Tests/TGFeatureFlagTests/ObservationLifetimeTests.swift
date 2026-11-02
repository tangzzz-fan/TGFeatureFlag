import Testing
import Foundation
import Observation
import os
@testable import TGFeatureFlagCore

@Suite("Observation Lifetime Tests")
struct ObservationLifetimeTests {

    @Test("Block-based observation unregisters when its owner is released")
    func unregistersOnRelease() {
        let name = Notification.Name("TGFeatureFlagTests.observationProbe")
        let count = OSAllocatedUnfairLock(initialState: 0)

        func install() {
            let observation = NotificationObservation(name: name) {
                count.withLock { $0 += 1 }
            }
            NotificationCenter.default.post(name: name, object: nil)
            #expect(count.withLock { $0 } == 1)
            withExtendedLifetime(observation) {}
        }

        install()

        // The owner is gone by now. Releasing it must unregister, otherwise the closure
        // lives for the lifetime of the process and keeps firing.
        NotificationCenter.default.post(name: name, object: nil)
        #expect(count.withLock { $0 } == 1)
    }

    @MainActor
    @Test("UserDefaults observation is opt-in")
    func observationIsOptIn() {
        #expect(FeatureFlagService().isObservingUserDefaults == false)
        #expect(FeatureFlagService(observeUserDefaults: true).isObservingUserDefaults)
    }

    @MainActor
    @Test("Opt-in service re-resolves when UserDefaults changes")
    func reactsToUserDefaultsChange() async {
        let service = FeatureFlagService(observeUserDefaults: true)
        let invalidated = OSAllocatedUnfairLock(initialState: false)

        withObservationTracking {
            _ = service.value(for: BoolTestFeature.booleanFeature)
        } onChange: {
            invalidated.withLock { $0 = true }
        }

        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)

        let fired = await waitUntil { invalidated.withLock { $0 } }
        #expect(fired, "an opt-in service must re-resolve on a UserDefaults change")
    }
}
