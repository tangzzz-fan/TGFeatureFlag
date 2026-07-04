# TGFeatureFlag

[![CI](https://github.com/tangzzz-fan/TGFeatureFlag/actions/workflows/ci.yml/badge.svg)](https://github.com/tangzzz-fan/TGFeatureFlag/actions/workflows/ci.yml)

A powerful, flexible, and type-safe feature flag framework for Apple platforms, built with Swift 6 and the Observation framework.

TGFeatureFlag decouples feature releases from code deployment, enabling safer releases, A/B testing, percentage-based rollouts, and dynamic configuration management.

## Platforms

iOS 17+, macOS 14+, tvOS 17+, watchOS 10+

## Features

- **Protocol-Oriented Design**: Define flags using enums conforming to `FeatureFlagKey`.
- **Type-Safe Values**: Support for `Bool`, `String`, `Int`, and `Double` values.
- **Priority Chain Resolution**: Flexible provider system with `.highest`, `.lowest`, and `.custom(Int)` priorities.
- **Async Provider Support**: `AsyncFeatureFlagProvider` protocol for remote config services (Firebase, LaunchDarkly, etc.).
- **Percentage-Based Rollouts**: `RolloutProvider` for deterministic, per-user feature rollouts.
- **Flag Namespacing**: `FeatureFlagGroup` and `GroupedFeatureFlag` for organizing flags into logical groups.
- **Diagnostic Logging**: `FeatureFlagLogger` protocol to observe which provider resolved each flag.
- **SwiftUI Ready**: Built on `@Observable` for seamless reactive UI updates.
- **Swift 6 Concurrency Safe**: `@MainActor`-isolated service, `Sendable` providers.
- **Built-in Debug Tools**: Runtime override view with editors for all value types.

## Installation

### Swift Package Manager

Add `TGFeatureFlag` to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/tangzzz-fan/TGFeatureFlag.git", from: "0.4.0")
]
```

Or in Xcode: **File → Add Package Dependencies**, then enter the repository URL.

## Continuous Integration

GitHub Actions runs `swift build` and `swift test` automatically for pushes and pull requests targeting `main`. The workflow file lives at `.github/workflows/ci.yml`.

## Usage

### 1. Define Feature Flags

Create an enum conforming to `FeatureFlagKey`. The `defaultValue` property supports `Bool`, `String`, `Int`, and `Double`.

```swift
import TGFeatureFlag

enum AppFeature: String, FeatureFlagKey, CaseIterable {
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

    var description: String {
        switch self {
        case .newProfileDesign: return "New Profile UI"
        case .apiBaseUrl: return "API Base URL"
        case .maxRetryCount: return "Max Retry Count"
        }
    }
}
```

### 2. Setup the Service

Initialize `FeatureFlagService` and register providers in priority order.

```swift
@main
struct MyApp: App {
    @State private var service = FeatureFlagService()

    init() {
        let s = FeatureFlagService()

        // Attach a diagnostic logger (optional)
        s.setLogger(MyLogger())

        // 1. Debug overrides (highest priority)
        s.register(provider: DebugProvider(), priority: .highest)

        // 2. Remote config (async provider)
        s.register(provider: MyRemoteProvider(), priority: .custom(80))

        // 3. UserDefaults
        s.register(provider: UserDefaultsProvider(), priority: .custom(40))

        // 4. Local fallback (lowest priority)
        s.register(provider: LocalProvider(), priority: .lowest)

        _service = State(initialValue: s)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .featureFlagService(service)
        }
    }
}
```

### 3. Use in SwiftUI

#### FeatureGate — Conditional View Rendering

```swift
FeatureGate(AppFeature.newProfileDesign) {
    NewProfileView()
} fallback: {
    OldProfileView()
}
```

#### Environment Access

```swift
struct ContentView: View {
    @Environment(FeatureFlagService.self) var service

    var body: some View {
        if service.isEnabled(AppFeature.newProfileDesign) {
            Text("New Design")
        }
        let url: String = service.value(for: AppFeature.apiBaseUrl)
        let retries: Int = service.value(for: AppFeature.maxRetryCount)
    }
}
```

### 4. Async Providers (Remote Config)

Implement `AsyncFeatureFlagProvider` for remote config services. The sync `value(for:)` returns cached values; call `refresh()` to fetch updates.

```swift
final class MyRemoteProvider: AsyncFeatureFlagProvider, @unchecked Sendable {
    let name = "Remote Config"
    private var cache: [String: Any] = [:]

    func value(for key: String) -> Any? { cache[key] }

    func fetchValues() async throws {
        // Fetch from your remote config service
        let values = try await RemoteConfig.fetch()
        cache = values
    }
}

// Trigger refresh from your UI
let failures = await service.refresh()
```

### 5. Percentage-Based Rollouts

Use `RolloutProvider` to gradually release features to a percentage of users. Results are deterministic per user ID.

```swift
let rollout = RolloutProvider(userId: currentUser.id)
rollout.setRollout(for: AppFeature.newProfileDesign, percentage: 50) // 50% of users
service.register(provider: rollout, priority: .custom(80))
```

### 6. Flag Namespacing (Groups)

Organize flags into groups with automatic key prefixing using `GroupedFeatureFlag`.

```swift
enum CheckoutFeature: String, FeatureFlagKey, GroupedFeatureFlag {
    case v2Flow = "v2Flow"
    case newPayment = "newPayment"

    var defaultValue: Any { false }

    static var group: FeatureFlagGroup {
        FeatureFlagGroup(prefix: "checkout")
    }
}

// Provider lookup uses qualified keys: "checkout.v2Flow", "checkout.newPayment"
service.isEnabled(CheckoutFeature.v2Flow)
```

### 7. Diagnostic Logging

Implement `FeatureFlagLogger` to observe which provider resolved each flag. Useful for production debugging and analytics.

```swift
struct ConsoleLogger: FeatureFlagLogger {
    func log(flag: String, resolvedBy provider: String?, value: Any?) {
        print("[Flag] \(flag) = \(value ?? "nil") (via: \(provider ?? "default"))")
    }
}

service.setLogger(ConsoleLogger())
```

### 8. Debug View

Include `FeatureFlagDebugView` in your app for runtime flag overrides. Supports editors for `Bool`, `String`, `Int`, and `Double`.

```swift
NavigationLink("Debug Flags") {
    FeatureFlagDebugView<AppFeature>()
}
```

## Architecture

The framework is built around five core files:

| Component | Role |
|-----------|------|
| `FeatureFlagKey` | Protocol defining flag identity, default value, and description. |
| `FeatureFlagProvider` | Protocol for pluggable value sources. |
| `AsyncFeatureFlagProvider` | Extension for providers that fetch values asynchronously. |
| `FeatureFlagGroup` | Namespace support via `GroupedFeatureFlag` protocol. |
| `FeatureFlagService` | `@MainActor @Observable` orchestrator that resolves values across the provider chain. |

### Priority Chain

Providers are sorted by priority (highest first). When a value is requested, the service iterates through the chain and returns the first non-nil result. If no provider has a value, the flag's `defaultValue` is used.

| Priority | Use Case |
|----------|----------|
| `.highest` | Debug overrides, QA tools |
| `.custom(80)` | Remote config, rollout providers |
| `.custom(40)` | UserDefaults, persisted settings |
| `.lowest` | Local defaults, fallback providers |

### Built-in Providers

| Provider | Description |
|----------|-------------|
| `DebugProvider` | Runtime overrides for development and QA. |
| `UserDefaultsProvider` | Reads from `UserDefaults` or a custom suite. |
| `LocalProvider` | Static in-memory values as a fallback. |
| `RolloutProvider` | Deterministic percentage-based rollouts per user. |

## License

This project is available under the MIT License. See [LICENSE](LICENSE) for details.
