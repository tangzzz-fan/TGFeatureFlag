import Foundation
import Testing
@testable import TGFeatureFlagCore

private enum WideningDoubleFeature: String, TypedFeatureFlag {
    case ratio = "widening_double"

    var typedDefaultValue: Double { 0.5 }
}

private enum WideningIntFeature: String, TypedFeatureFlag {
    case retries = "widening_int"

    var typedDefaultValue: Int { 3 }
}

/// Numeric widening on the typed read path.
///
/// `JSONDecoder` cannot tell `1` from `1.0`, so a backend that writes a whole number for a
/// double flag produces `.int`. Refusing it would make a correctly-configured flag run on its
/// shipped default — indistinguishable, from the app's side, from a flag that was turned off.
/// The read accepts it and reports `valueWidened` instead.
@Suite("Numeric widening")
struct ValueWideningTests {

    @Test("A Double flag reads an integer payload instead of falling back")
    func doubleReadsInt() {
        let resolver = FeatureFlagResolver()
        resolver.register(
            provider: LocalProvider(flags: [WideningDoubleFeature.ratio.lookupKey: .int(1)]),
            priority: .highest
        )

        #expect(resolver.value(for: WideningDoubleFeature.ratio) == 1.0)
    }

    @Test("The widening is reported, and not as a type mismatch")
    func wideningIsReportedAsItsOwnEvent() {
        let sink = TestEventSink()
        let resolver = FeatureFlagResolver()
        resolver.setEventSink(sink)
        resolver.register(
            provider: LocalProvider(flags: [WideningDoubleFeature.ratio.lookupKey: .int(2)]),
            priority: .highest
        )

        #expect(resolver.value(for: WideningDoubleFeature.ratio) == 2.0)

        let widened = sink.events.compactMap { event -> (String, String, FeatureFlagValue)? in
            guard case .valueWidened(let flag, let expected, let actual) = event else { return nil }
            return (flag, expected, actual)
        }
        #expect(widened.count == 1)
        #expect(widened.first?.0 == WideningDoubleFeature.ratio.lookupKey)
        #expect(widened.first?.1 == "Double")
        #expect(widened.first?.2 == .int(2))

        let mismatches = sink.events.filter {
            if case .typeMismatch = $0 { return true }
            return false
        }
        #expect(mismatches.isEmpty)
    }

    @Test("An exact double resolves without a notice")
    func exactDoubleIsSilent() {
        let sink = TestEventSink()
        let resolver = FeatureFlagResolver()
        resolver.setEventSink(sink)
        resolver.register(
            provider: LocalProvider(flags: [WideningDoubleFeature.ratio.lookupKey: .double(2.5)]),
            priority: .highest
        )

        #expect(resolver.value(for: WideningDoubleFeature.ratio) == 2.5)
        #expect(typeNotices(in: sink).isEmpty)
    }

    @Test("Widening is one-directional: an Int flag rejects a fractional double")
    func intDoesNotNarrow() {
        let sink = TestEventSink()
        let resolver = FeatureFlagResolver()
        resolver.setEventSink(sink)
        resolver.register(
            provider: LocalProvider(flags: [WideningIntFeature.retries.lookupKey: .double(1.5)]),
            priority: .highest
        )

        // Truncating to 1 would be a silent lossy read, so it stays a mismatch.
        #expect(resolver.value(for: WideningIntFeature.retries) == 3)
        #expect(resolver.rawValue(for: WideningIntFeature.retries) == .double(1.5))

        let mismatches = sink.events.compactMap { event -> FeatureFlagValue? in
            guard case .typeMismatch(_, _, let actual) = event else { return nil }
            return actual
        }
        #expect(mismatches == [.double(1.5)])
    }

    @Test("Nothing else widens: an integer is not a boolean")
    func intIsNotABool() {
        let resolver = FeatureFlagResolver()
        resolver.register(
            provider: LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .int(1)]),
            priority: .highest
        )

        // `1` meaning "on" is a guess about the backend's intent, not a compatible shape.
        #expect(resolver.value(for: BoolTestFeature.booleanFeature) == false)
    }

    @Test("Snapshots widen the same way the service does")
    func snapshotWidens() {
        let snapshot = FeatureFlagSnapshot(values: [WideningDoubleFeature.ratio.lookupKey: .int(4)])

        // Parity matters: a Redux app reading a snapshot and a service-driven app reading the
        // same provider payload must not disagree about the value.
        #expect(snapshot.value(for: WideningDoubleFeature.ratio) == 4.0)
        #expect(snapshot.rawValue(for: WideningDoubleFeature.ratio) == .int(4))
    }

    @Test("A backend payload written as 1.0 now resolves, and still says why")
    func rolloutPayloadResolves() throws {
        let payload = Data(#"{"rollouts":{"widening_double":{"percentage":100,"value":1.0}}}"#.utf8)
        let configuration = try JSONDecoder().decode(RolloutConfiguration.self, from: payload)

        // The JSON still decodes as an integer — that is a `JSONDecoder` fact, not a bug here.
        #expect(configuration[WideningDoubleFeature.ratio.lookupKey]?.value == .int(1))

        let resolver = FeatureFlagResolver()
        resolver.register(
            provider: LocalProvider(
                flags: [
                    WideningDoubleFeature.ratio.lookupKey:
                        configuration[WideningDoubleFeature.ratio.lookupKey]?.value ?? .double(0)
                ]
            ),
            priority: .highest
        )

        #expect(resolver.value(for: WideningDoubleFeature.ratio) == 1.0)
    }

    @Test("A sink that opted out of type notices stays quiet")
    func noticesAreGatedByOptions() {
        let sink = TestEventSink()
        let resolver = FeatureFlagResolver()
        resolver.setEventSink(sink, options: [.exposures])
        resolver.register(
            provider: LocalProvider(flags: [WideningDoubleFeature.ratio.lookupKey: .int(1)]),
            priority: .highest
        )

        #expect(resolver.value(for: WideningDoubleFeature.ratio) == 1.0)
        #expect(typeNotices(in: sink).isEmpty)
    }

    /// Widening and mismatch events, ignoring the exposures every read also produces.
    private func typeNotices(in sink: TestEventSink) -> [FeatureFlagEvent] {
        sink.events.filter { event in
            switch event {
            case .valueWidened, .typeMismatch: return true
            default: return false
            }
        }
    }
}
