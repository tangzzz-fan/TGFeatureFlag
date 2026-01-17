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
