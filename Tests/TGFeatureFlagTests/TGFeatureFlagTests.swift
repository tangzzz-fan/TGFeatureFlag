import Testing
import Foundation
import os
@testable import TGFeatureFlag

// Define test features
enum TestFeature: String, FeatureFlagKey {
    case booleanFeature = "test_bool"
    case stringFeature = "test_string"
    case intFeature = "test_int"

    var defaultValue: FeatureFlagValue {
        switch self {
        case .booleanFeature: return .bool(false)
        case .stringFeature: return .string("default")
        case .intFeature: return .int(42)
        }
    }
}

// Test logger for verifying resolution events
final class TestLogger: FeatureFlagLogger, @unchecked Sendable {
    struct LogEntry: Sendable {
        let flag: String
        let provider: String?
        let value: FeatureFlagValue?
    }

    var entries: [LogEntry] = []
    private let lock = NSLock()

    func log(flag: String, resolvedBy provider: String?, value: FeatureFlagValue?) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(LogEntry(flag: flag, provider: provider, value: value))
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
            TestFeature.booleanFeature.lookupKey: .bool(true)
        ])

        service.register(provider: debugProvider, priority: .highest)
        service.register(provider: localProvider, priority: .lowest)

        #expect(service.isEnabled(TestFeature.booleanFeature) == true)

        debugProvider.setOverride(for: TestFeature.booleanFeature, value: .bool(false))
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)

        debugProvider.setOverride(for: TestFeature.booleanFeature, value: nil)
        #expect(service.isEnabled(TestFeature.booleanFeature) == true)
    }

    // MARK: - Generic Value Tests

    @Test("String Value Handling")
    func stringValue() {
        let debugProvider = DebugProvider()
        service.register(provider: debugProvider, priority: .highest)

        #expect(service.stringValue(for: TestFeature.stringFeature) == "default")

        debugProvider.setOverride(for: TestFeature.stringFeature, value: .string("overridden"))
        #expect(service.stringValue(for: TestFeature.stringFeature) == "overridden")
    }

    @Test("Int Value Handling")
    func intValue() {
        let debugProvider = DebugProvider()
        service.register(provider: debugProvider, priority: .highest)

        #expect(service.intValue(for: TestFeature.intFeature) == 42)

        debugProvider.setOverride(for: TestFeature.intFeature, value: .int(100))
        #expect(service.intValue(for: TestFeature.intFeature) == 100)
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

        userDefaults.set(true, forKey: TestFeature.booleanFeature.lookupKey)
        userDefaults.set("persisted", forKey: TestFeature.stringFeature.lookupKey)

        #expect(service.isEnabled(TestFeature.booleanFeature) == true)
        #expect(service.stringValue(for: TestFeature.stringFeature) == "persisted")
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
        let lowProvider = LocalProvider(flags: [TestFeature.booleanFeature.lookupKey: .bool(false)])
        let midProvider = LocalProvider(flags: [TestFeature.booleanFeature.lookupKey: .bool(true)])
        let highProvider = LocalProvider(flags: [TestFeature.booleanFeature.lookupKey: .bool(false)])

        service.register(provider: lowProvider, priority: .custom(10))
        service.register(provider: highProvider, priority: .custom(100))
        service.register(provider: midProvider, priority: .custom(50))

        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
    }

    @Test("Mixed Priority Levels")
    func mixedPriority() {
        let highestProvider = LocalProvider(flags: [TestFeature.stringFeature.lookupKey: .string("highest")])
        let customProvider = LocalProvider(flags: [TestFeature.stringFeature.lookupKey: .string("custom")])
        let lowestProvider = LocalProvider(flags: [TestFeature.stringFeature.lookupKey: .string("lowest")])

        service.register(provider: lowestProvider, priority: .lowest)
        service.register(provider: customProvider, priority: .custom(50))
        service.register(provider: highestProvider, priority: .highest)

        #expect(service.stringValue(for: TestFeature.stringFeature) == "highest")
    }

    @Test("Default Fallback with Empty Provider Chain")
    func emptyProviderChain() {
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
        #expect(service.stringValue(for: TestFeature.stringFeature) == "default")
        #expect(service.intValue(for: TestFeature.intFeature) == 42)
    }

    @Test("DebugProvider Reset")
    func debugProviderReset() {
        let debugProvider = DebugProvider()
        service.register(provider: debugProvider, priority: .highest)

        debugProvider.setOverride(for: TestFeature.booleanFeature, value: .bool(true))
        #expect(service.isEnabled(TestFeature.booleanFeature) == true)

        debugProvider.reset()
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
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

    @Test("FeatureFlagLogger Logs Resolution")
    func loggerLogsResolution() {
        let logger = TestLogger()
        service.setLogger(logger)

        let localProvider = LocalProvider(flags: [TestFeature.booleanFeature.lookupKey: .bool(true)])
        service.register(provider: localProvider, priority: .highest)

        _ = service.isEnabled(TestFeature.booleanFeature)

        #expect(logger.entries.count == 1)
        #expect(logger.entries.first?.flag == TestFeature.booleanFeature.lookupKey)
        #expect(logger.entries.first?.provider == "Local")
    }

    @Test("FeatureFlagLogger Logs Default Fallback")
    func loggerLogsDefaultFallback() {
        let logger = TestLogger()
        service.setLogger(logger)

        _ = service.isEnabled(TestFeature.booleanFeature)

        #expect(logger.entries.count == 1)
        #expect(logger.entries.first?.provider == nil)
        #expect(logger.entries.first?.flag == TestFeature.booleanFeature.lookupKey)
    }

    @Test("LocalProvider enabledFeatures Initializer")
    func localProviderEnabledFeatures() {
        let provider = LocalProvider(enabledFeatures: [TestFeature.booleanFeature])

        #expect(provider.value(for: TestFeature.booleanFeature.lookupKey) == .bool(true))
        #expect(provider.value(for: TestFeature.stringFeature.lookupKey) == nil)
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
                TestFeature.booleanFeature.lookupKey: .bool(true),
                TestFeature.stringFeature.lookupKey: .string("async_value")
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
    func asyncProviderRefresh() async {
        let asyncProvider = MockAsyncProvider()
        service.register(provider: asyncProvider, priority: .highest)

        #expect(service.isEnabled(TestFeature.booleanFeature) == false)

        let failures = await service.refresh()
        #expect(failures == 0)
        #expect(asyncProvider.fetchCount == 1)

        #expect(service.isEnabled(TestFeature.booleanFeature) == true)
        #expect(service.stringValue(for: TestFeature.stringFeature) == "async_value")
    }

    @Test("Async Provider Refresh with Failure")
    func asyncProviderRefreshFailure() async {
        let asyncProvider = MockAsyncProvider()
        asyncProvider.shouldFail = true
        service.register(provider: asyncProvider, priority: .highest)

        let failures = await service.refresh()
        #expect(failures == 1)
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
    }

    @Test("Mixed Sync and Async Providers")
    func mixedProviders() async {
        let syncProvider = DebugProvider()
        let asyncProvider = MockAsyncProvider()

        service.register(provider: syncProvider, priority: .highest)
        service.register(provider: asyncProvider, priority: .custom(50))

        #expect(service.isEnabled(TestFeature.booleanFeature) == false)

        await service.refresh()
        #expect(service.isEnabled(TestFeature.booleanFeature) == true)

        syncProvider.setOverride(for: TestFeature.booleanFeature, value: .bool(false))
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
    }
}

// Grouped feature flags for testing
enum GroupedTestFeature: String, FeatureFlagKey, GroupedFeatureFlag {
    case featureA = "featureA"
    case featureB = "featureB"

    var defaultValue: FeatureFlagValue { .bool(false) }

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
        rollout.setRollout(for: TestFeature.booleanFeature, percentage: 100)
        service.register(provider: rollout, priority: .highest)

        #expect(service.isEnabled(TestFeature.booleanFeature) == true)
    }

    @Test("RolloutProvider 0% Rollout blocks fallthrough")
    func rollout0Percent() {
        let rollout = RolloutProvider(userId: "test-user")
        rollout.setRollout(for: TestFeature.booleanFeature, percentage: 0)
        let local = LocalProvider(flags: [TestFeature.booleanFeature.lookupKey: .bool(true)])

        service.register(provider: rollout, priority: .highest)
        service.register(provider: local, priority: .lowest)

        // 0% must return false and must NOT fall through to local true
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
        #expect(rollout.value(for: TestFeature.booleanFeature.lookupKey) == .bool(false))
    }

    @Test("RolloutProvider Deterministic Hash")
    func rolloutDeterministic() {
        let rollout = RolloutProvider(userId: "deterministic-user-42")
        rollout.setRollout(for: TestFeature.booleanFeature, percentage: 50)

        let result1 = rollout.value(for: TestFeature.booleanFeature.lookupKey)
        let result2 = rollout.value(for: TestFeature.booleanFeature.lookupKey)

        #expect(result1 == result2)
    }

    @Test("RolloutProvider Stable Hash Across Instances")
    func rolloutStableAcrossInstances() {
        let a = RolloutProvider(userId: "stable-user")
        let b = RolloutProvider(userId: "stable-user")
        a.setRollout(for: TestFeature.booleanFeature, percentage: 50)
        b.setRollout(for: TestFeature.booleanFeature, percentage: 50)

        #expect(
            a.value(for: TestFeature.booleanFeature.lookupKey)
                == b.value(for: TestFeature.booleanFeature.lookupKey)
        )

        // Fixed FNV-1a vector: bucket for "vector-user:test_bool" must be stable.
        let input = "vector-user:test_bool"
        let bucket = Int(StableHash.fnv1a64(input) % 100)
        #expect(bucket == Int(StableHash.fnv1a64(input) % 100))
        #expect((0..<100).contains(bucket))
    }

    @Test("RolloutProvider Custom Value")
    func rolloutCustomValue() {
        let rollout = RolloutProvider(userId: "custom-user")
        rollout.setRollout(
            for: TestFeature.stringFeature,
            percentage: 100,
            value: .string("rolled_out_url")
        )
        service.register(provider: rollout, priority: .highest)

        #expect(service.stringValue(for: TestFeature.stringFeature) == "rolled_out_url")
    }

    @Test("RolloutProvider Remove Rollout")
    func rolloutRemove() {
        let rollout = RolloutProvider(userId: "test-user")
        rollout.setRollout(for: TestFeature.booleanFeature, percentage: 100)
        service.register(provider: rollout, priority: .highest)

        #expect(service.isEnabled(TestFeature.booleanFeature) == true)

        rollout.removeRollout(for: TestFeature.booleanFeature)
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
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
            TestFeature.booleanFeature.lookupKey: .bool(true),
            TestFeature.stringFeature.lookupKey: .string("from-local"),
            TestFeature.intFeature.lookupKey: .int(7)
        ])
        resolver.register(provider: local, priority: .highest)

        let snapshot = resolver.snapshot(for: [
            TestFeature.booleanFeature,
            TestFeature.stringFeature,
            TestFeature.intFeature
        ])

        #expect(snapshot.isEnabled(TestFeature.booleanFeature) == true)
        #expect(snapshot.string(for: TestFeature.stringFeature.lookupKey) == "from-local")
        #expect(snapshot.int(for: TestFeature.intFeature.lookupKey) == 7)

        #expect(resolver.value(for: TestFeature.booleanFeature) == .bool(true))
        #expect(resolver.value(for: TestFeature.stringFeature) == .string("from-local"))
        #expect(resolver.value(for: TestFeature.intFeature) == .int(7))
    }

    @Test("Resolver refresh updates snapshot")
    func resolverRefresh() async {
        let resolver = FeatureFlagResolver()
        let asyncProvider = MockAsyncProvider()
        resolver.register(provider: asyncProvider, priority: .highest)

        #expect(resolver.isEnabled(TestFeature.booleanFeature) == false)

        let failures = await resolver.refresh()
        #expect(failures == 0)

        let snapshot = resolver.snapshot(for: [TestFeature.booleanFeature, TestFeature.stringFeature])
        #expect(snapshot.isEnabled(TestFeature.booleanFeature) == true)
        #expect(snapshot.string(for: TestFeature.stringFeature.lookupKey) == "async_value")
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
