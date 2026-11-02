import Testing
import SwiftUI
// The umbrella module must keep re-exporting both halves, otherwise splitting the package
// into Core + SwiftUI silently breaks every existing `import TGFeatureFlag`.
import TGFeatureFlag

@MainActor
@Suite("Umbrella module")
struct UmbrellaImportTests {

    @Test("Core symbols and SwiftUI gates are both reachable through the umbrella")
    func bothHalvesAreReachable() {
        let service = FeatureFlagService()
        service.register(
            provider: LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(true)]),
            priority: .highest
        )

        #expect(service.isEnabled(BoolTestFeature.booleanFeature))

        let snapshot = service.snapshot(for: [BoolTestFeature.booleanFeature])
        let gate = FeatureGate(BoolTestFeature.booleanFeature, snapshot: snapshot) {
            Text("on")
        } fallback: {
            Text("off")
        }
        _ = gate.body
    }
}
