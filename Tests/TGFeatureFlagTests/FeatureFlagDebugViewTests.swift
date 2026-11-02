import SwiftUI
import Testing
@testable import TGFeatureFlagCore
@testable import TGFeatureFlagSwiftUI

private enum DebugBoolFeature: String, TypedFeatureFlag, CaseIterable {
    case onByDefault = "debug_bool_on"
    case offByDefault = "debug_bool_off"

    var typedDefaultValue: Bool {
        switch self {
        case .onByDefault: return true
        case .offByDefault: return false
        }
    }
}

private enum DebugIntFeature: String, TypedFeatureFlag, CaseIterable {
    case retries = "debug_int"

    var typedDefaultValue: Int { 3 }
}

private enum DebugDoubleFeature: String, TypedFeatureFlag, CaseIterable {
    case ratio = "debug_double"

    var typedDefaultValue: Double { 1.5 }
}

private enum DebugStringFeature: String, TypedFeatureFlag, CaseIterable {
    case banner = "debug_string"

    var typedDefaultValue: String { "shipped copy" }
}

@MainActor
@Suite("Feature flag debug screen")
struct FeatureFlagDebugViewTests {

    // MARK: - Display model

    @Test("A flag with no resolved value shows its default")
    func fallsBackToDefault() {
        let model = FeatureFlagDebugEditorModel(
            defaultValue: .bool(true),
            resolved: nil,
            isOverridden: false
        )

        #expect(model.currentValue == .bool(true))
        #expect(model.displayText == "ON")
        #expect(model.hasTypeMismatch == false)
    }

    @Test("Each declared type renders in its own unit")
    func displaysEveryKind() {
        let bool = FeatureFlagDebugEditorModel(defaultValue: .bool(false), resolved: .bool(true), isOverridden: false)
        let int = FeatureFlagDebugEditorModel(defaultValue: .int(3), resolved: .int(7), isOverridden: false)
        let double = FeatureFlagDebugEditorModel(defaultValue: .double(1.5), resolved: .double(2), isOverridden: false)
        let string = FeatureFlagDebugEditorModel(defaultValue: .string("a"), resolved: .string("b"), isOverridden: false)

        #expect(bool.displayText == "ON")
        #expect(int.displayText == "7")
        // Two decimals because a ratio shown as "2" reads like an integer count.
        #expect(double.displayText == "2.00")
        #expect(string.displayText == "b")
    }

    @Test("The editor family comes from the key, not from the stored value")
    func kindFollowsDeclaredType() {
        let model = FeatureFlagDebugEditorModel(
            defaultValue: .bool(false),
            resolved: .string("legacy"),
            isOverridden: false
        )

        #expect(model.kind == .bool)
        #expect(model.hasTypeMismatch)
        #expect(model.displayText == "\"legacy\" (expected bool)")
        #expect(model.currentValueDescription == "\"legacy\"")
    }

    @Test("Reset writes the key's default back to the row")
    func resetUsesDefault() {
        let model = FeatureFlagDebugEditorModel(defaultValue: .int(3), resolved: .int(9), isOverridden: true)

        #expect(model.resetValue == .int(3))
        #expect(model.isOverridden)
    }

    // MARK: - Source precedence

    @Test("An explicit snapshot wins over the environment service")
    func snapshotBeatsService() {
        let service = FeatureFlagService()
        service.register(
            provider: LocalProvider(flags: [DebugBoolFeature.offByDefault.lookupKey: .bool(false)]),
            priority: .highest
        )
        let snapshot = FeatureFlagSnapshot(values: [DebugBoolFeature.offByDefault.lookupKey: .bool(true)])

        let resolved = FeatureFlagDebugResolution.value(
            for: DebugBoolFeature.offByDefault,
            snapshot: snapshot,
            service: service
        )

        #expect(resolved == .bool(true))
    }

    @Test("A snapshot missing the key does not fall through to the service")
    func snapshotDoesNotLeakToService() {
        let service = FeatureFlagService()
        service.register(
            provider: LocalProvider(flags: [DebugBoolFeature.offByDefault.lookupKey: .bool(true)]),
            priority: .highest
        )

        let resolved = FeatureFlagDebugResolution.value(
            for: DebugBoolFeature.offByDefault,
            snapshot: FeatureFlagSnapshot(),
            service: service
        )

        // Showing the service value here would display a decision the Store is not running.
        #expect(resolved == nil)
    }

    @Test("The service answers when no snapshot is supplied")
    func serviceOnlySource() {
        let service = FeatureFlagService()
        service.register(
            provider: LocalProvider(flags: [DebugIntFeature.retries.lookupKey: .int(5)]),
            priority: .highest
        )

        let resolved = FeatureFlagDebugResolution.value(
            for: DebugIntFeature.retries,
            snapshot: nil,
            service: service
        )

        #expect(resolved == .int(5))
    }

    @Test("Either an override set or a debug provider marks the row")
    func overrideMarkers() {
        let debug = DebugProvider()

        #expect(
            FeatureFlagDebugResolution.isOverridden(
                for: DebugStringFeature.banner,
                overriddenKeys: [DebugStringFeature.banner.lookupKey],
                debugProvider: nil
            )
        )
        #expect(
            !FeatureFlagDebugResolution.isOverridden(
                for: DebugStringFeature.banner,
                overriddenKeys: [],
                debugProvider: debug
            )
        )

        debug.setOverride(for: DebugStringFeature.banner, value: .string("临时文案"))

        #expect(
            FeatureFlagDebugResolution.isOverridden(
                for: DebugStringFeature.banner,
                overriddenKeys: [],
                debugProvider: debug
            )
        )
    }

    // MARK: - Rendering

    @Test("The snapshot screen renders without a service in the environment")
    func snapshotScreenRenders() {
        let snapshot = FeatureFlagSnapshot(
            values: [
                DebugBoolFeature.onByDefault.lookupKey: .bool(false),
                DebugBoolFeature.offByDefault.lookupKey: .bool(true),
            ]
        )
        let screen = FeatureFlagDebugView<DebugBoolFeature>(
            snapshot: snapshot,
            overriddenKeys: [DebugBoolFeature.offByDefault.lookupKey]
        ) { _, _ in }

        // Previously every row read `@Environment(FeatureFlagService.self)`, which traps when
        // the value is missing — so a Redux app could not open this screen at all.
        let renderer = ImageRenderer(content: screen.frame(width: 320, height: 480))

        #expect(renderer.nsImage != nil)
    }

    @Test("A screen with no source explains itself instead of trapping")
    func degradesWithoutSource() {
        let screen = FeatureFlagDebugView<DebugBoolFeature>()

        _ = screen.body
    }

    @Test("The service screen renders with a service injected")
    func serviceScreenRenders() {
        let service = FeatureFlagService()
        service.register(provider: DebugProvider(), priority: .highest)

        // Rendered rather than read: `.featureFlagService(_:)` returns a `ModifiedContent`,
        // and SwiftUI forbids calling `body` on one directly.
        let renderer = ImageRenderer(
            content: FeatureFlagDebugView<DebugDoubleFeature>()
                .featureFlagService(service)
                .frame(width: 320, height: 480)
        )

        #expect(renderer.nsImage != nil)
    }
}
