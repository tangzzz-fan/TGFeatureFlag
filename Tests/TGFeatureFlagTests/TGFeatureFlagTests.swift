import Testing
import Foundation
import os
@testable import TGFeatureFlagCore

// Define test features
// One value type per enum: `TypedFeatureFlag.Value` is an associated type, so boolean switches
// and configuration values cannot share an enum.
enum BoolTestFeature: String, TypedFeatureFlag {
    case booleanFeature = "test_bool"
    var typedDefaultValue: Bool { false }
}

enum StringTestFeature: String, TypedFeatureFlag {
    case stringFeature = "test_string"
    var typedDefaultValue: String { "default" }
}

enum IntTestFeature: String, TypedFeatureFlag {
    case intFeature = "test_int"
    var typedDefaultValue: Int { 42 }
}

// Test sink for verifying feature-flag events.
final class TestEventSink: FeatureFlagEventSink, @unchecked Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [FeatureFlagEvent]())

    var events: [FeatureFlagEvent] { storage.withLock { $0 } }

    var resolutions: [(flag: String, provider: String?, value: FeatureFlagValue)] {
        events.compactMap { event in
            guard case .resolved(let flag, let provider, let value) = event else { return nil }
            return (flag, provider, value)
        }
    }

    var exposures: [(flag: String, value: FeatureFlagValue)] {
        events.compactMap { event in
            guard case .exposure(let flag, let value) = event else { return nil }
            return (flag, value)
        }
    }

    func receive(_ event: FeatureFlagEvent) {
        storage.withLock { $0.append(event) }
    }
}

@MainActor
@Suite("TGFeatureFlag Tests")
struct TGFeatureFlagTests {

    let service: FeatureFlagService

    init() {
        service = FeatureFlagService()
    }

    // MARK: - Priority Chain Tests

    @Test("Priority Chain Verification")
    func priorityChain() {
        let debugProvider = DebugProvider()
        let localProvider = LocalProvider(flags: [
            BoolTestFeature.booleanFeature.lookupKey: .bool(true)
        ])

        service.register(provider: debugProvider, priority: .highest)
        service.register(provider: localProvider, priority: .lowest)

        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == true)

        debugProvider.setOverride(for: BoolTestFeature.booleanFeature, value: .bool(false))
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == false)

        debugProvider.setOverride(for: BoolTestFeature.booleanFeature, value: nil)
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == true)
    }

    // MARK: - Generic Value Tests

    @Test("String Value Handling")
    func stringValue() {
        let debugProvider = DebugProvider()
        service.register(provider: debugProvider, priority: .highest)

        #expect(service.value(for: StringTestFeature.stringFeature) == "default")

        debugProvider.setOverride(for: StringTestFeature.stringFeature, value: .string("overridden"))
        #expect(service.value(for: StringTestFeature.stringFeature) == "overridden")
    }

    @Test("Int Value Handling")
    func intValue() {
        let debugProvider = DebugProvider()
        service.register(provider: debugProvider, priority: .highest)

        #expect(service.value(for: IntTestFeature.intFeature) == 42)

        debugProvider.setOverride(for: IntTestFeature.intFeature, value: .int(100))
        #expect(service.value(for: IntTestFeature.intFeature) == 100)
    }

    // MARK: - UserDefaults Provider Tests

    @Test("UserDefaults Integration")
    func userDefaultsProvider() {
        let suiteName = "TestFeatureFlagSuite"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            #expect(Bool(false), "Failed to create UserDefaults suite")
            return
        }
        userDefaults.removePersistentDomain(forName: suiteName)

        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let provider = UserDefaultsProvider(userDefaults: userDefaults)
        service.register(provider: provider, priority: .highest)

        userDefaults.set(true, forKey: BoolTestFeature.booleanFeature.lookupKey)
        userDefaults.set("persisted", forKey: StringTestFeature.stringFeature.lookupKey)

        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == true)
        #expect(service.value(for: StringTestFeature.stringFeature) == "persisted")
    }
}

@MainActor
@Suite("v0.2.0 Enhancement Tests")
struct EnhancementTests {

    let service: FeatureFlagService

    init() {
        service = FeatureFlagService()
    }

    @Test("Custom Priority Ordering")
    func customPriority() {
        let lowProvider = LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(false)])
        let midProvider = LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(true)])
        let highProvider = LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(false)])

        service.register(provider: lowProvider, priority: .custom(10))
        service.register(provider: highProvider, priority: .custom(100))
        service.register(provider: midProvider, priority: .custom(50))

        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == false)
    }

    @Test("Mixed Priority Levels")
    func mixedPriority() {
        let highestProvider = LocalProvider(flags: [StringTestFeature.stringFeature.lookupKey: .string("highest")])
        let customProvider = LocalProvider(flags: [StringTestFeature.stringFeature.lookupKey: .string("custom")])
        let lowestProvider = LocalProvider(flags: [StringTestFeature.stringFeature.lookupKey: .string("lowest")])

        service.register(provider: lowestProvider, priority: .lowest)
        service.register(provider: customProvider, priority: .custom(50))
        service.register(provider: highestProvider, priority: .highest)

        #expect(service.value(for: StringTestFeature.stringFeature) == "highest")
    }

    @Test("Default Fallback with Empty Provider Chain")
    func emptyProviderChain() {
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == false)
        #expect(service.value(for: StringTestFeature.stringFeature) == "default")
        #expect(service.value(for: IntTestFeature.intFeature) == 42)
    }

    @Test("DebugProvider Reset")
    func debugProviderReset() {
        let debugProvider = DebugProvider()
        service.register(provider: debugProvider, priority: .highest)

        debugProvider.setOverride(for: BoolTestFeature.booleanFeature, value: .bool(true))
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == true)

        debugProvider.reset()
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == false)
    }

    @Test("Provider ofType Lookup")
    func providerOfTypeLookup() {
        let debugProvider = DebugProvider()
        service.register(provider: debugProvider, priority: .highest)
        service.register(provider: LocalProvider(flags: [:]), priority: .lowest)

        let found = service.provider(ofType: DebugProvider.self)
        #expect(found != nil)
        #expect(found?.name == "Debug Override")

        let notFound = service.provider(ofType: UserDefaultsProvider.self)
        #expect(notFound == nil)
    }

    @Test("Resolution events name the resolving provider")
    func resolutionEventNamesProvider() {
        let sink = TestEventSink()
        service.setEventSink(sink, options: .resolutions)

        let localProvider = LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(true)])
        service.register(provider: localProvider, priority: .highest)

        _ = service.isEnabled(BoolTestFeature.booleanFeature)

        #expect(sink.resolutions.count == 1)
        #expect(sink.resolutions.first?.flag == BoolTestFeature.booleanFeature.lookupKey)
        #expect(sink.resolutions.first?.provider == "Local")
    }

    @Test("Resolution events report a default fallback with no provider")
    func resolutionEventDefaultFallback() {
        let sink = TestEventSink()
        service.setEventSink(sink, options: .resolutions)

        _ = service.isEnabled(BoolTestFeature.booleanFeature)

        #expect(sink.resolutions.count == 1)
        #expect(sink.resolutions.first?.provider == nil)
        #expect(sink.resolutions.first?.flag == BoolTestFeature.booleanFeature.lookupKey)
    }

    @Test("LocalProvider enabledFeatures Initializer")
    func localProviderEnabledFeatures() {
        let provider = LocalProvider(enabledFeatures: [BoolTestFeature.booleanFeature])

        #expect(provider.value(for: BoolTestFeature.booleanFeature.lookupKey) == .bool(true))
        #expect(provider.value(for: StringTestFeature.stringFeature.lookupKey) == nil)
    }
}

// Mock async provider for testing
final class MockAsyncProvider: AsyncFeatureFlagProvider, Sendable {
    let name: String
    private let lock = OSAllocatedUnfairLock(initialState: Cache())
    private let shouldFailLock = OSAllocatedUnfairLock(initialState: false)

    struct Cache: Sendable {
        var values: [String: FeatureFlagValue] = [:]
        var fetchCount = 0
    }

    var shouldFail: Bool {
        get { shouldFailLock.withLock { $0 } }
        set { shouldFailLock.withLock { $0 = newValue } }
    }

    var fetchCount: Int {
        lock.withLock { $0.fetchCount }
    }

    init(name: String = "MockAsync") {
        self.name = name
    }

    func value(for key: String) -> FeatureFlagValue? {
        lock.withLock { $0.values[key] }
    }

    func fetchValues() async throws {
        lock.withLock { $0.fetchCount += 1 }
        if shouldFail {
            throw NSError(
                domain: "MockAsyncProvider",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Simulated failure"]
            )
        }
        try await Task.sleep(for: .milliseconds(10))
        lock.withLock { cache in
            cache.values = [
                BoolTestFeature.booleanFeature.lookupKey: .bool(true),
                StringTestFeature.stringFeature.lookupKey: .string("async_value")
            ]
        }
    }
}

@MainActor
@Suite("v0.3.0 Async Provider Tests")
struct AsyncProviderTests {

    let service: FeatureFlagService

    init() {
        service = FeatureFlagService()
    }

    @Test("Async Provider Refresh")
    func asyncProviderRefresh() async throws {
        let asyncProvider = MockAsyncProvider()
        service.register(provider: asyncProvider, priority: .highest)

        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == false)

        let report = try await service.refresh()
        #expect(report.failures == 0)
        #expect(report.isSuccess)
        #expect(asyncProvider.fetchCount == 1)

        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == true)
        #expect(service.value(for: StringTestFeature.stringFeature) == "async_value")
    }

    @Test("Async Provider Refresh with Failure")
    func asyncProviderRefreshFailure() async throws {
        let asyncProvider = MockAsyncProvider()
        asyncProvider.shouldFail = true
        service.register(provider: asyncProvider, priority: .highest)

        let report = try await service.refresh()
        #expect(report.failures == 1)
        #expect(report.outcomes.first?.providerName == "MockAsync")
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == false)
    }

    @Test("Mixed Sync and Async Providers")
    func mixedProviders() async throws {
        let syncProvider = DebugProvider()
        let asyncProvider = MockAsyncProvider()

        service.register(provider: syncProvider, priority: .highest)
        service.register(provider: asyncProvider, priority: .custom(50))

        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == false)

        try await service.refresh()
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == true)

        syncProvider.setOverride(for: BoolTestFeature.booleanFeature, value: .bool(false))
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == false)
    }
}

// Grouped feature flags for testing
enum GroupedTestFeature: String, TypedFeatureFlag, GroupedFeatureFlag {
    case featureA = "featureA"
    case featureB = "featureB"

    var typedDefaultValue: Bool { false }

    static var group: FeatureFlagGroup {
        FeatureFlagGroup(prefix: "testgroup")
    }
}

@MainActor
@Suite("v0.4.0 Rollout and Group Tests")
struct RolloutAndGroupTests {

    let service: FeatureFlagService

    init() {
        service = FeatureFlagService()
    }

    @Test("RolloutProvider 100% Rollout")
    func rollout100Percent() {
        let rollout = RolloutProvider(userId: "test-user")
        rollout.setRollout(for: BoolTestFeature.booleanFeature, percentage: 100)
        service.register(provider: rollout, priority: .highest)

        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == true)
    }

    @Test("RolloutProvider 0% Rollout blocks fallthrough")
    func rollout0Percent() {
        let rollout = RolloutProvider(userId: "test-user")
        rollout.setRollout(for: BoolTestFeature.booleanFeature, percentage: 0)
        let local = LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(true)])

        service.register(provider: rollout, priority: .highest)
        service.register(provider: local, priority: .lowest)

        // 0% must return false and must NOT fall through to local true
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == false)
        #expect(rollout.value(for: BoolTestFeature.booleanFeature.lookupKey) == .bool(false))
    }

    @Test("RolloutProvider Deterministic Hash")
    func rolloutDeterministic() {
        let rollout = RolloutProvider(userId: "deterministic-user-42")
        rollout.setRollout(for: BoolTestFeature.booleanFeature, percentage: 50)

        let result1 = rollout.value(for: BoolTestFeature.booleanFeature.lookupKey)
        let result2 = rollout.value(for: BoolTestFeature.booleanFeature.lookupKey)

        #expect(result1 == result2)
    }

    @Test("RolloutProvider Stable Hash Across Instances")
    func rolloutStableAcrossInstances() {
        let a = RolloutProvider(userId: "stable-user")
        let b = RolloutProvider(userId: "stable-user")
        a.setRollout(for: BoolTestFeature.booleanFeature, percentage: 50)
        b.setRollout(for: BoolTestFeature.booleanFeature, percentage: 50)

        #expect(
            a.value(for: BoolTestFeature.booleanFeature.lookupKey)
                == b.value(for: BoolTestFeature.booleanFeature.lookupKey)
        )
    }

    @Test("Rollout hash matches pinned FNV-1a vectors")
    func rolloutHashVector() {
        // Pinned vectors, not a self-comparison: this is the contract. Changing the hash
        // re-buckets every user and silently shifts live rollouts, so it must be deliberate.
        #expect(StableHash.fnv1a64("") == 14_695_981_039_346_656_037)
        #expect(StableHash.fnv1a64("vector-user:test_bool") == 15_449_056_510_182_236_017)
        #expect(StableHash.fnv1a64("demo-user-001:checkout.v2_flow") == 1_993_456_019_063_078_937)
    }

    @Test("RolloutProvider Custom Value")
    func rolloutCustomValue() {
        let rollout = RolloutProvider(userId: "custom-user")
        rollout.setRollout(
            for: StringTestFeature.stringFeature,
            percentage: 100,
            value: .string("rolled_out_url")
        )
        service.register(provider: rollout, priority: .highest)

        #expect(service.value(for: StringTestFeature.stringFeature) == "rolled_out_url")
    }

    @Test("RolloutProvider Remove Rollout")
    func rolloutRemove() {
        let rollout = RolloutProvider(userId: "test-user")
        rollout.setRollout(for: BoolTestFeature.booleanFeature, percentage: 100)
        service.register(provider: rollout, priority: .highest)

        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == true)

        rollout.removeRollout(for: BoolTestFeature.booleanFeature)
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == false)
    }

    @Test("FeatureFlagGroup Qualified Key")
    func groupQualifiedKey() {
        let feature = GroupedTestFeature.featureA
        #expect(feature.qualifiedKey == "testgroup.featureA")
        #expect(feature.lookupKey == "testgroup.featureA")
    }

    @Test("FeatureFlagGroup Provider Lookup Uses Qualified Key")
    func groupProviderLookup() {
        let localProvider = LocalProvider(flags: [
            "testgroup.featureA": .bool(true),
            "testgroup.featureB": .bool(false)
        ])
        service.register(provider: localProvider, priority: .highest)

        #expect(service.isEnabled(GroupedTestFeature.featureA) == true)
        #expect(service.isEnabled(GroupedTestFeature.featureB) == false)
    }

    @Test("FeatureFlagGroup Custom Separator")
    func groupCustomSeparator() {
        let group = FeatureFlagGroup(prefix: "app", separator: "/")
        #expect(group.qualifiedKey(for: "myFlag") == "app/myFlag")
    }

    @Test("FeatureFlagGroup Fallback to Default When Key Not Found")
    func groupFallback() {
        let localProvider = LocalProvider(flags: [
            "featureA": .bool(true) // Wrong key (no prefix)
        ])
        service.register(provider: localProvider, priority: .highest)

        #expect(service.isEnabled(GroupedTestFeature.featureA) == false)
    }

    @Test("Grouped debug override uses qualified key")
    func groupedDebugOverride() {
        let debug = DebugProvider()
        let local = LocalProvider(flags: [
            GroupedTestFeature.featureA.lookupKey: .bool(false)
        ])
        service.register(provider: debug, priority: .highest)
        service.register(provider: local, priority: .lowest)

        #expect(service.isEnabled(GroupedTestFeature.featureA) == false)

        debug.setOverride(for: GroupedTestFeature.featureA, value: .bool(true))
        #expect(debug.value(for: "testgroup.featureA") == .bool(true))
        #expect(debug.value(for: "featureA") == nil)
        #expect(service.isEnabled(GroupedTestFeature.featureA) == true)
    }
}

@Suite("v0.5.0 Resolver Snapshot Tests")
struct ResolverSnapshotTests {

    @Test("Resolver snapshot matches value(for:)")
    func snapshotMatchesValues() {
        let resolver = FeatureFlagResolver()
        let local = LocalProvider(flags: [
            BoolTestFeature.booleanFeature.lookupKey: .bool(true),
            StringTestFeature.stringFeature.lookupKey: .string("from-local"),
            IntTestFeature.intFeature.lookupKey: .int(7)
        ])
        resolver.register(provider: local, priority: .highest)

        // A snapshot is built per key type: `snapshot(for:)` takes one homogeneous key sequence.
        let boolSnapshot = resolver.snapshot(for: [BoolTestFeature.booleanFeature])
        let stringSnapshot = resolver.snapshot(for: [StringTestFeature.stringFeature])
        let intSnapshot = resolver.snapshot(for: [IntTestFeature.intFeature])

        #expect(boolSnapshot.isEnabled(BoolTestFeature.booleanFeature) == true)
        #expect(stringSnapshot.string(for: StringTestFeature.stringFeature.lookupKey) == "from-local")
        #expect(intSnapshot.int(for: IntTestFeature.intFeature.lookupKey) == 7)

        // Typed reads unwrap to the declared type, so no `.bool(...)` matching is needed.
        #expect(resolver.value(for: BoolTestFeature.booleanFeature) == true)
        #expect(resolver.value(for: StringTestFeature.stringFeature) == "from-local")
        #expect(resolver.value(for: IntTestFeature.intFeature) == 7)
        #expect(resolver.rawValue(for: BoolTestFeature.booleanFeature) == .bool(true))
    }

    @Test("Resolver refresh updates snapshot")
    func resolverRefresh() async throws {
        let resolver = FeatureFlagResolver()
        let asyncProvider = MockAsyncProvider()
        resolver.register(provider: asyncProvider, priority: .highest)

        #expect(resolver.isEnabled(BoolTestFeature.booleanFeature) == false)

        let report = try await resolver.refresh()
        #expect(report.failures == 0)

        let snapshot = resolver.snapshot(for: [BoolTestFeature.booleanFeature])
        #expect(snapshot.isEnabled(BoolTestFeature.booleanFeature) == true)

        let stringSnapshot = resolver.snapshot(for: [StringTestFeature.stringFeature])
        #expect(stringSnapshot.string(for: StringTestFeature.stringFeature.lookupKey) == "async_value")
    }

    @Test("FeatureFlagSnapshot Codable round-trip")
    func snapshotCodable() throws {
        let original = FeatureFlagSnapshot(values: [
            "a": .bool(true),
            "b": .string("hello"),
            "c": .int(3),
            "d": .double(1.5)
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FeatureFlagSnapshot.self, from: data)
        #expect(decoded == original)
    }
}

@MainActor
@Suite("Resolution contract")
struct ResolutionContractTests {

    private func makeService(_ values: [Bool], priority: FeatureFlagPriority) -> FeatureFlagService {
        let service = FeatureFlagService()
        for value in values {
            service.register(
                provider: LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(value)]),
                priority: priority
            )
        }
        return service
    }

    @Test("Equal .highest priorities: the first registered provider wins")
    func equalHighestPriorityFirstWins() {
        let service = makeService([true, false], priority: .highest)
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == true)
    }

    @Test("Equal .custom priorities: the first registered provider wins")
    func equalCustomPriorityFirstWins() {
        let service = makeService([true, false], priority: .custom(50))
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == true)
    }

    @Test("Equal .lowest priorities: the first registered provider wins")
    func equalLowestPriorityFirstWins() {
        let service = makeService([true, false], priority: .lowest)
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == true)
    }

    @Test("Registration order never overrides priority")
    func priorityBeatsRegistrationOrder() {
        let service = FeatureFlagService()
        service.register(
            provider: LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(true)]),
            priority: .lowest
        )
        service.register(
            provider: LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(false)]),
            priority: .custom(10)
        )
        #expect(service.isEnabled(BoolTestFeature.booleanFeature) == false)
    }
}
