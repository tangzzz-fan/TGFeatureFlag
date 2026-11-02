import Testing
import SwiftUI
@testable import TGFeatureFlagCore
@testable import TGFeatureFlagSwiftUI

@MainActor
@Suite("FeatureGate")
struct FeatureGateTests {

    private typealias Gate = FeatureGate<BoolTestFeature, Text, Text>

    @Test("An explicit snapshot wins over the environment service")
    func snapshotTakesPrecedence() {
        let service = FeatureFlagService()
        service.register(
            provider: LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(false)]),
            priority: .highest
        )
        let snapshot = FeatureFlagSnapshot(
            values: [BoolTestFeature.booleanFeature.lookupKey: .bool(true)]
        )

        // Preferring the service here would quietly reintroduce the second source of truth.
        #expect(Gate.resolvesEnabled(BoolTestFeature.booleanFeature, snapshot: snapshot, service: service))
    }

    @Test("Falls back to the service when no snapshot is supplied")
    func serviceDriven() {
        let service = FeatureFlagService()
        service.register(
            provider: LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(true)]),
            priority: .highest
        )

        #expect(Gate.resolvesEnabled(BoolTestFeature.booleanFeature, snapshot: nil, service: service))
    }

    @Test("A snapshot decides on its own with no service present")
    func snapshotOnly() {
        let snapshot = FeatureFlagSnapshot(
            values: [BoolTestFeature.booleanFeature.lookupKey: .bool(true)]
        )

        #expect(Gate.resolvesEnabled(BoolTestFeature.booleanFeature, snapshot: snapshot, service: nil))
    }

    @Test("Both modes construct through the same type")
    func bothModesConstruct() {
        let snapshot = FeatureFlagSnapshot(
            values: [BoolTestFeature.booleanFeature.lookupKey: .bool(true)]
        )

        let withSnapshot = FeatureGate(BoolTestFeature.booleanFeature, snapshot: snapshot) {
            Text("on")
        } fallback: {
            Text("off")
        }

        let withService = FeatureGate(BoolTestFeature.booleanFeature) {
            Text("on")
        } fallback: {
            Text("off")
        }

        let snapshotNoFallback = FeatureGate(BoolTestFeature.booleanFeature, snapshot: snapshot) {
            Text("on")
        }

        let serviceNoFallback = FeatureGate(BoolTestFeature.booleanFeature) {
            Text("on")
        }

        // Only the snapshot-driven gates can be evaluated here: a detached view has no
        // environment, so the service-driven ones would (correctly) hit the missing-service
        // assertion. Constructing all four is the API-regression guard.
        _ = withSnapshot.body
        _ = snapshotNoFallback.body
        _ = withService
        _ = serviceNoFallback
    }
}
