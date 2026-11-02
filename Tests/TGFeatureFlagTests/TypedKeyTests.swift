import Testing
import Foundation
@testable import TGFeatureFlagCore

@MainActor
@Suite("Typed keys")
struct TypedKeyTests {

    // Compile-time guarantees, recorded as negative cases. Uncommenting any of these must fail
    // to build; they are here so a future refactor that loosens the constraints is noticed.
    //
    //   resolver.isEnabled(StringTestFeature.stringFeature)
    //   // error: requires that 'String' conform to 'Bool'
    //
    //   let text: String = resolver.value(for: BoolTestFeature.booleanFeature)
    //   // error: cannot convert value of type 'Bool' to specified type 'String'
    //
    //   let raw: FeatureFlagValue = resolver.value(for: BoolTestFeature.booleanFeature)
    //   // error: cannot convert value of type 'Bool' to specified type 'FeatureFlagValue'

    @Test("Reads unwrap to the type the key declares")
    func typedReads() {
        let resolver = FeatureFlagResolver()
        resolver.register(
            provider: LocalProvider(flags: [
                BoolTestFeature.booleanFeature.lookupKey: .bool(true),
                StringTestFeature.stringFeature.lookupKey: .string("hello"),
                IntTestFeature.intFeature.lookupKey: .int(9)
            ]),
            priority: .highest
        )

        let enabled: Bool = resolver.value(for: BoolTestFeature.booleanFeature)
        let text: String = resolver.value(for: StringTestFeature.stringFeature)
        let count: Int = resolver.value(for: IntTestFeature.intFeature)

        #expect(enabled)
        #expect(text == "hello")
        #expect(count == 9)
    }

    @Test("The untyped default is derived from the typed one")
    func defaultValueIsDerived() {
        #expect(BoolTestFeature.booleanFeature.defaultValue == .bool(false))
        #expect(StringTestFeature.stringFeature.defaultValue == .string("default"))
        #expect(IntTestFeature.intFeature.defaultValue == .int(42))
    }

    @Test("A stored value of the wrong case falls back to the typed default")
    func mismatchedCaseFallsBack() {
        let resolver = FeatureFlagResolver()
        // A remote payload that sends a string where the key declares a boolean.
        resolver.register(
            provider: LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .string("oops")]),
            priority: .highest
        )

        // The call site stays non-optional and gets the declared default.
        #expect(resolver.value(for: BoolTestFeature.booleanFeature) == false)

        // The raw layer still shows what the provider actually returned.
        #expect(resolver.rawValue(for: BoolTestFeature.booleanFeature) == .string("oops"))
    }

    @Test("Snapshots unwrap and fall back the same way")
    func snapshotTypedReads() {
        let snapshot = FeatureFlagSnapshot(values: [
            BoolTestFeature.booleanFeature.lookupKey: .bool(true),
            StringTestFeature.stringFeature.lookupKey: .int(3)
        ])

        #expect(snapshot.value(for: BoolTestFeature.booleanFeature) == true)
        // Wrong case in the snapshot: fall back rather than trap.
        #expect(snapshot.value(for: StringTestFeature.stringFeature) == "default")
        #expect(snapshot.rawValue(for: StringTestFeature.stringFeature) == .int(3))
    }

    @Test("An absent key resolves to the typed default")
    func absentKeyUsesTypedDefault() {
        let resolver = FeatureFlagResolver()
        #expect(resolver.value(for: IntTestFeature.intFeature) == 42)
        #expect(FeatureFlagSnapshot().value(for: IntTestFeature.intFeature) == 42)
    }

    @Test("Grouped typed keys keep the qualified lookup")
    func groupedTypedKey() {
        let resolver = FeatureFlagResolver()
        resolver.register(
            provider: LocalProvider(flags: ["testgroup.featureA": .bool(true)]),
            priority: .highest
        )

        #expect(resolver.isEnabled(GroupedTestFeature.featureA))
        #expect(GroupedTestFeature.featureA.defaultValue == .bool(false))
    }
}
