# TGFeatureFlag

A powerful, flexible, and type-safe Feature Flag framework for iOS and macOS, built with Swift 6 and the Observation framework.

TGFeatureFlag allows you to decouple feature release from code deployment, enabling safer releases, A/B testing, and dynamic configuration management.

## Features

- **Protocol-Oriented Design**: Define your flags using enums conforming to `FeatureFlagKey`.
- **Type-Safe Configuration**: Support for `Bool`, `String`, `Int`, and `Double` values.
- **Priority Chain Resolution**: Flexible provider system (Debug > Settings.bundle > Remote Config > Local Default).
- **SwiftUI Ready**: Built on the `@Observable` macro for seamless UI updates.
- **Built-in Debug Tools**: Includes a debug view for runtime overrides.
- **Concurrency Safe**: Thread-safe implementations for providers.

## Installation

### Swift Package Manager

Add `TGFeatureFlag` to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/tangzzz-fan/TGFeatureFlag.git", from: "0.0.1")
]
```

## Usage

### 1. Define Your Feature Flags

Create an enum conforming to `FeatureFlagKey`. The `defaultValue` property supports `Bool`, `String`, `Int`, and `Double`.

```swift
import TGFeatureFlag

enum AppFeature: String, FeatureFlagKey {
    case newProfileDesign = "feature_new_profile"
    case apiBaseUrl = "config_api_base_url"
    case maxRetryCount = "config_retry_count"

    var defaultValue: Any {
        switch self {
        case .newProfileDesign: return false
        case .apiBaseUrl: return "https://api.production.com"
        case .maxRetryCount: return 3
        }
    }
}
```

### 2. Setup the Service

Initialize the `FeatureFlagService` and register your providers.

```swift
import TGFeatureFlag

@main
struct MyApp: App {
    @State private var featureService = FeatureFlagService()
    
    init() {
        let service = FeatureFlagService()
        
        // 1. Debug Provider (Highest Priority - Runtime Overrides)
        service.register(provider: DebugProvider(), priority: .highest)
        
        // 2. UserDefaults/Settings.bundle Provider
        if let defaults = UserDefaults(suiteName: "group.com.myapp") {
            service.register(provider: UserDefaultsProvider(userDefaults: defaults), priority: .highest)
        }
        
        // 3. Local Default Provider (Lowest Priority - Fallback)
        // Note: You usually don't need to explicitly register a local provider if you just rely on `defaultValue` in the enum.
        
        self._featureService = State(initialValue: service)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(featureService)
        }
    }
}
```

### 3. Use in SwiftUI

#### Using `FeatureGate`

The `FeatureGate` view conditionally renders content based on a boolean flag.

```swift
FeatureGate(AppFeature.newProfileDesign) {
    NewProfileView()
} fallback: {
    OldProfileView()
}
```

#### Using Environment

Access the service directly for more complex logic.

```swift
struct ContentView: View {
    @Environment(FeatureFlagService.self) private var featureService
    
    var body: some View {
        if featureService.isEnabled(AppFeature.newProfileDesign) {
            Text("New Design")
        }
    }
}
```

### 4. Configuration Values (Non-Boolean)

Retrieve typed values for configuration flags.

```swift
let urlString: String = featureService.value(for: AppFeature.apiBaseUrl)
let retryCount: Int = featureService.value(for: AppFeature.maxRetryCount)
```

### 5. Debug View

Include the `FeatureFlagDebugView` in your app (e.g., in a developer settings screen) to toggle flags at runtime.

```swift
FeatureFlagDebugView(
    features: AppFeature.allCases,
    provider: debugProvider // Pass your DebugProvider instance
)
```

## Architecture

The framework is built around three core components:

1.  **`FeatureFlagKey`**: Defines the identity and default value of a flag.
2.  **`FeatureFlagProvider`**: Abstract source of flag values (e.g., `DebugProvider`, `UserDefaultsProvider`).
3.  **`FeatureFlagService`**: The central manager that iterates through registered providers to resolve the final value.

### Priority Chain

When you request a value, the service checks providers in the order they were registered (or based on priority). The first provider to return a non-nil value determines the result. If no provider has a value, the `defaultValue` from the key is used.
