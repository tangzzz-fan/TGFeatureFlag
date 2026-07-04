import Testing
import Foundation
@testable import TGFeatureFlag

// Define test features
enum TestFeature: String, FeatureFlagKey {
    case booleanFeature = "test_bool"
    case stringFeature = "test_string"
    case intFeature = "test_int"
    
    var defaultValue: Any {
        switch self {
        case .booleanFeature: return false
        case .stringFeature: return "default"
        case .intFeature: return 42
        }
    }
}

// Test logger for verifying resolution events
final class TestLogger: FeatureFlagLogger, @unchecked Sendable {
    struct LogEntry {
        let flag: String
        let provider: String?
        let value: Any?
    }
    
    var entries: [LogEntry] = []
    private let lock = NSLock()
    
    func log(flag: String, resolvedBy provider: String?, value: Any?) {
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
        // 1. Setup Providers
        let debugProvider = DebugProvider()
        let localProvider = LocalProvider(flags: [
            TestFeature.booleanFeature.rawValue: true
        ])
        
        // 2. Register with Priorities
        service.register(provider: debugProvider, priority: .highest)
        service.register(provider: localProvider, priority: .lowest)
        
        // 3. Initial Check (Should take from Local)
        #expect(service.isEnabled(TestFeature.booleanFeature) == true)
        
        // 4. Set Override (Should take from Debug)
        debugProvider.setOverride(for: TestFeature.booleanFeature, value: false)
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
        
        // 5. Remove Override (Should fallback to Local)
        debugProvider.setOverride(for: TestFeature.booleanFeature, value: nil)
        #expect(service.isEnabled(TestFeature.booleanFeature) == true)
    }
    
    // MARK: - Generic Value Tests
    
    @Test("String Value Handling")
    func stringValue() {
        // 1. Setup
        let debugProvider = DebugProvider()
        service.register(provider: debugProvider, priority: .highest)
        
        // 2. Check Default
        let value: String = service.value(for: TestFeature.stringFeature)
        #expect(value == "default")
        
        // 3. Override
        debugProvider.setOverride(for: TestFeature.stringFeature, value: "overridden")
        
        // 4. Check Override
        let newValue: String = service.value(for: TestFeature.stringFeature)
        #expect(newValue == "overridden")
    }
    
    @Test("Int Value Handling")
    func intValue() {
        // 1. Setup
        let debugProvider = DebugProvider()
        service.register(provider: debugProvider, priority: .highest)
        
        // 2. Check Default
        let value: Int = service.value(for: TestFeature.intFeature)
        #expect(value == 42)
        
        // 3. Override
        debugProvider.setOverride(for: TestFeature.intFeature, value: 100)
        
        // 4. Check Override
        let newValue: Int = service.value(for: TestFeature.intFeature)
        #expect(newValue == 100)
    }
    
    // MARK: - UserDefaults Provider Tests
    
    @Test("UserDefaults Integration")
    func userDefaultsProvider() {
        // 1. Setup specific suite to avoid polluting standard
        let suiteName = "TestFeatureFlagSuite"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            #expect(Bool(false), "Failed to create UserDefaults suite")
            return
        }
        userDefaults.removePersistentDomain(forName: suiteName)
        
        // Cleanup after test
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        
        let provider = UserDefaultsProvider(userDefaults: userDefaults)
        service.register(provider: provider, priority: .highest)
        
        // 2. Set value in UserDefaults
        userDefaults.set(true, forKey: TestFeature.booleanFeature.rawValue)
        userDefaults.set("persisted", forKey: TestFeature.stringFeature.rawValue)
        
        // 3. Check Service
        #expect(service.isEnabled(TestFeature.booleanFeature) == true)
        let stringVal: String = service.value(for: TestFeature.stringFeature)
        #expect(stringVal == "persisted")
    }
}

@MainActor
@Suite("v0.2.0 Enhancement Tests")
struct EnhancementTests {
    
    let service: FeatureFlagService
    
    init() {
        service = FeatureFlagService()
    }
    
    // MARK: - Custom Priority Tests
    
    @Test("Custom Priority Ordering")
    func customPriority() {
        let lowProvider = LocalProvider(flags: [TestFeature.booleanFeature.rawValue: false])
        let midProvider = LocalProvider(flags: [TestFeature.booleanFeature.rawValue: true])
        let highProvider = LocalProvider(flags: [TestFeature.booleanFeature.rawValue: false])
        
        // Register out of order: low, high, mid
        service.register(provider: lowProvider, priority: .custom(10))
        service.register(provider: highProvider, priority: .custom(100))
        service.register(provider: midProvider, priority: .custom(50))
        
        // Highest custom priority (100) should win -> false
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
    }
    
    @Test("Mixed Priority Levels")
    func mixedPriority() {
        let highestProvider = LocalProvider(flags: [TestFeature.stringFeature.rawValue: "highest"])
        let customProvider = LocalProvider(flags: [TestFeature.stringFeature.rawValue: "custom"])
        let lowestProvider = LocalProvider(flags: [TestFeature.stringFeature.rawValue: "lowest"])
        
        service.register(provider: lowestProvider, priority: .lowest)
        service.register(provider: customProvider, priority: .custom(50))
        service.register(provider: highestProvider, priority: .highest)
        
        let value: String = service.value(for: TestFeature.stringFeature)
        #expect(value == "highest")
    }
    
    // MARK: - Default Fallback Tests
    
    @Test("Default Fallback with Empty Provider Chain")
    func emptyProviderChain() {
        // No providers registered, should use default
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
        let str: String = service.value(for: TestFeature.stringFeature)
        #expect(str == "default")
        let num: Int = service.value(for: TestFeature.intFeature)
        #expect(num == 42)
    }
    
    // MARK: - DebugProvider Reset Tests
    
    @Test("DebugProvider Reset")
    func debugProviderReset() {
        let debugProvider = DebugProvider()
        service.register(provider: debugProvider, priority: .highest)
        
        debugProvider.setOverride(for: TestFeature.booleanFeature, value: true)
        #expect(service.isEnabled(TestFeature.booleanFeature) == true)
        
        debugProvider.reset()
        // After reset, should fall back to default (false)
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
    }
    
    // MARK: - Provider Lookup Tests
    
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
    
    // MARK: - Logger Tests
    
    @Test("FeatureFlagLogger Logs Resolution")
    func loggerLogsResolution() {
        let logger = TestLogger()
        service.setLogger(logger)
        
        let localProvider = LocalProvider(flags: [TestFeature.booleanFeature.rawValue: true])
        service.register(provider: localProvider, priority: .highest)
        
        _ = service.isEnabled(TestFeature.booleanFeature)
        
        #expect(logger.entries.count == 1)
        #expect(logger.entries.first?.flag == TestFeature.booleanFeature.rawValue)
        #expect(logger.entries.first?.provider == "Local")
    }
    
    @Test("FeatureFlagLogger Logs Default Fallback")
    func loggerLogsDefaultFallback() {
        let logger = TestLogger()
        service.setLogger(logger)
        
        // No providers, should log default fallback
        _ = service.isEnabled(TestFeature.booleanFeature)
        
        #expect(logger.entries.count == 1)
        #expect(logger.entries.first?.provider == nil)
        #expect(logger.entries.first?.flag == TestFeature.booleanFeature.rawValue)
    }
    
    // MARK: - LocalProvider enabledFeatures Init Tests
    
    @Test("LocalProvider enabledFeatures Initializer")
    func localProviderEnabledFeatures() {
        let provider = LocalProvider(enabledFeatures: [TestFeature.booleanFeature])
        
        let boolVal = provider.value(for: TestFeature.booleanFeature.rawValue)
        #expect(boolVal as? Bool == true)
        
        let missingVal = provider.value(for: TestFeature.stringFeature.rawValue)
        #expect(missingVal == nil)
    }
}

// Mock async provider for testing
final class MockAsyncProvider: AsyncFeatureFlagProvider, @unchecked Sendable {
    let name: String
    private var cache: [String: Any] = [:]
    private let lock = NSLock()
    var fetchCount = 0
    var shouldFail = false
    
    init(name: String = "MockAsync") {
        self.name = name
    }
    
    func value(for key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }
    
    func fetchValues() async throws {
        fetchCount += 1
        if shouldFail {
            throw NSError(domain: "MockAsyncProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated failure"])
        }
        // Simulate async fetch
        try await Task.sleep(for: .milliseconds(10))
        let newCache: [String: Any] = [
            TestFeature.booleanFeature.rawValue: true,
            TestFeature.stringFeature.rawValue: "async_value"
        ]
        lock.withLock {
            cache = newCache
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
        
        // Before refresh, no cached values -> falls back to default
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
        
        // Refresh
        let failures = await service.refresh()
        #expect(failures == 0)
        #expect(asyncProvider.fetchCount == 1)
        
        // After refresh, cached values available
        #expect(service.isEnabled(TestFeature.booleanFeature) == true)
        let str: String = service.value(for: TestFeature.stringFeature)
        #expect(str == "async_value")
    }
    
    @Test("Async Provider Refresh with Failure")
    func asyncProviderRefreshFailure() async {
        let asyncProvider = MockAsyncProvider()
        asyncProvider.shouldFail = true
        service.register(provider: asyncProvider, priority: .highest)
        
        let failures = await service.refresh()
        #expect(failures == 1)
        
        // After failed refresh, still uses defaults
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
    }
    
    @Test("Mixed Sync and Async Providers")
    func mixedProviders() async {
        let syncProvider = DebugProvider()
        let asyncProvider = MockAsyncProvider()
        
        service.register(provider: syncProvider, priority: .highest)
        service.register(provider: asyncProvider, priority: .custom(50))
        
        // Sync provider has no override, async not yet refreshed -> default
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
        
        // Refresh async provider
        await service.refresh()
        
        // Async provider now has value
        #expect(service.isEnabled(TestFeature.booleanFeature) == true)
        
        // Sync override still takes priority
        syncProvider.setOverride(for: TestFeature.booleanFeature, value: false)
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
    }
}

// Grouped feature flags for testing
enum GroupedTestFeature: String, FeatureFlagKey, GroupedFeatureFlag {
    case featureA = "featureA"
    case featureB = "featureB"
    
    var defaultValue: Any { false }
    
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
    
    // MARK: - RolloutProvider Tests
    
    @Test("RolloutProvider 100% Rollout")
    func rollout100Percent() {
        let rollout = RolloutProvider(userId: "test-user")
        rollout.setRollout(for: TestFeature.booleanFeature, percentage: 100)
        service.register(provider: rollout, priority: .highest)
        
        #expect(service.isEnabled(TestFeature.booleanFeature) == true)
    }
    
    @Test("RolloutProvider 0% Rollout")
    func rollout0Percent() {
        let rollout = RolloutProvider(userId: "test-user")
        rollout.setRollout(for: TestFeature.booleanFeature, percentage: 0)
        service.register(provider: rollout, priority: .highest)
        
        // 0% means nil, falls back to default (false)
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
    }
    
    @Test("RolloutProvider Deterministic Hash")
    func rolloutDeterministic() {
        // Same user should always get same result
        let rollout = RolloutProvider(userId: "deterministic-user-42")
        rollout.setRollout(for: TestFeature.booleanFeature, percentage: 50)
        
        let result1 = rollout.value(for: TestFeature.booleanFeature.rawValue)
        let result2 = rollout.value(for: TestFeature.booleanFeature.rawValue)
        
        #expect(result1 as? Bool == result2 as? Bool)
    }
    
    @Test("RolloutProvider Custom Value")
    func rolloutCustomValue() {
        let rollout = RolloutProvider(userId: "custom-user")
        rollout.setRollout(for: TestFeature.stringFeature, percentage: 100, value: "rolled_out_url")
        service.register(provider: rollout, priority: .highest)
        
        let value: String = service.value(for: TestFeature.stringFeature)
        #expect(value == "rolled_out_url")
    }
    
    @Test("RolloutProvider Remove Rollout")
    func rolloutRemove() {
        let rollout = RolloutProvider(userId: "test-user")
        rollout.setRollout(for: TestFeature.booleanFeature, percentage: 100)
        service.register(provider: rollout, priority: .highest)
        
        #expect(service.isEnabled(TestFeature.booleanFeature) == true)
        
        rollout.removeRollout(for: TestFeature.booleanFeature)
        // After removal, falls back to default
        #expect(service.isEnabled(TestFeature.booleanFeature) == false)
    }
    
    // MARK: - FeatureFlagGroup Tests
    
    @Test("FeatureFlagGroup Qualified Key")
    func groupQualifiedKey() {
        let feature = GroupedTestFeature.featureA
        #expect(feature.qualifiedKey == "testgroup.featureA")
    }
    
    @Test("FeatureFlagGroup Provider Lookup Uses Qualified Key")
    func groupProviderLookup() {
        let localProvider = LocalProvider(flags: [
            "testgroup.featureA": true,
            "testgroup.featureB": false
        ])
        service.register(provider: localProvider, priority: .highest)
        
        // featureA should be found via qualified key
        #expect(service.isEnabled(GroupedTestFeature.featureA) == true)
        // featureB explicitly disabled
        #expect(service.isEnabled(GroupedTestFeature.featureB) == false)
    }
    
    @Test("FeatureFlagGroup Custom Separator")
    func groupCustomSeparator() {
        let group = FeatureFlagGroup(prefix: "app", separator: "/")
        #expect(group.qualifiedKey(for: "myFlag") == "app/myFlag")
    }
    
    @Test("FeatureFlagGroup Fallback to Default When Key Not Found")
    func groupFallback() {
        // No provider has the qualified key
        let localProvider = LocalProvider(flags: [
            "featureA": true // Wrong key (no prefix)
        ])
        service.register(provider: localProvider, priority: .highest)
        
        // Should not find "featureA" because lookup uses "testgroup.featureA"
        #expect(service.isEnabled(GroupedTestFeature.featureA) == false)
    }
}
