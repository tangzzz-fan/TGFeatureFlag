# TGFeatureFlag

[![CI](https://github.com/tangzzz-fan/TGFeatureFlag/actions/workflows/ci.yml/badge.svg)](https://github.com/tangzzz-fan/TGFeatureFlag/actions/workflows/ci.yml)

A type-safe feature flag framework for Apple platforms, built with Swift 6 strict concurrency.

TGFeatureFlag decouples feature releases from code deployment, enabling safer releases, A/B testing, percentage-based rollouts, and dynamic configuration.

## Platforms

iOS 17+, macOS 14+, tvOS 17+, watchOS 10+

## Two modes

| Mode | When to use | Source of truth |
|------|-------------|-----------------|
| **Resolver + Snapshot** (recommended for Redux) | TGReduxKit / any Store-as-SoT app | App Store after `dispatch(.loaded(snapshot))` |
| **FeatureFlagService** (`@Observable`) | Demo / non-Redux SwiftUI apps | The service itself |

This package does **not** depend on TGReduxKit. Redux apps adapt `FeatureFlagResolver` to their own `FeatureFlagFetching`-style port (see [TGReduxKit 5.0.1 Shopping demo](https://github.com/tangzzz-fan/TGReduxKit) as the reference wiring).

```text
AsyncProvider.fetchValues → Resolver.refresh
Resolver.snapshot(for:) → App Adapter → dispatch(.loaded)
Reducer projects → Views read Store (not Environment Service)
```

## Features

- **Typed values**: `FeatureFlagValue` (`bool` / `string` / `int` / `double`) — no `Any`, no resolution `fatalError`.
- **Sendable Resolver**: build cold `FeatureFlagSnapshot` values for Redux middleware.
- **Priority chain**: `.highest` / `.lowest` / `.custom(Int)`.
- **Async providers**: `AsyncFeatureFlagProvider` + `refresh()`.
- **Rollouts**: stable FNV-1a hashing (process-independent).
- **Grouping**: `FeatureFlagGroup` / `GroupedFeatureFlag` with unified `lookupKey`.
- **SwiftUI**: `FeatureGate` (Environment Service) and `SnapshotFeatureGate` (injected snapshot).

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/tangzzz-fan/TGFeatureFlag.git", from: "0.5.0")
]
```

## Continuous Integration

GitHub Actions runs `swift build` and `swift test` for pushes and PRs targeting `main`.

## Usage

### 1. Define Feature Flags

```swift
import TGFeatureFlag

enum AppFeature: String, FeatureFlagKey, CaseIterable {
    case newProfileDesign = "feature_new_profile"
    case apiBaseUrl = "config_api_base_url"
    case maxRetryCount = "config_retry_count"

    var defaultValue: FeatureFlagValue {
        switch self {
        case .newProfileDesign: return .bool(false)
        case .apiBaseUrl: return .string("https://api.production.com")
        case .maxRetryCount: return .int(3)
        }
    }
}
```

### 2a. Redux path — Resolver + Snapshot

```swift
let resolver = FeatureFlagResolver()
resolver.register(provider: DebugProvider(), priority: .highest)
resolver.register(provider: MyRemoteProvider(), priority: .custom(80))
resolver.register(provider: LocalProvider(flags: [:]), priority: .lowest)

_ = await resolver.refresh()
let snapshot = resolver.snapshot(for: AppFeature.allCases)

// App-owned adapter (mirrors TGReduxKit Shopping FeatureFlagFetching):
// map snapshot → domain DTO, then middleware dispatches .loaded(dto, now())
```

Illustrative adapter (lives in the app, not this package):

```swift
struct TGFFFetchingAdapter: FeatureFlagFetching {
    let resolver: FeatureFlagResolver

    func fetchSnapshot() async -> AppFeatureFlagSnapshot {
        _ = await resolver.refresh()
        let remote = resolver.snapshot(for: AppFeature.allCases)
        return AppFeatureFlagSnapshot(
            isNewProfileEnabled: remote.isEnabled(AppFeature.newProfileDesign)
            // ...map other keys
        )
    }
}

// Composition Root (TGReduxKit 5.0.1 style):
// makeFeatureFlagsMiddleware(featureFlags: adapter, now: { Date() })
```

SwiftUI with an injected snapshot (no `FeatureFlagService`):

```swift
SnapshotFeatureGate(AppFeature.newProfileDesign, snapshot: storeState.flags) {
    NewProfileView()
} fallback: {
    LegacyProfileView()
}
```

### 2b. Non-Redux path — FeatureFlagService

```swift
@main
struct MyApp: App {
    @State private var service = FeatureFlagService()

    init() {
        let s = FeatureFlagService()
        s.register(provider: DebugProvider(), priority: .highest)
        s.register(provider: LocalProvider(flags: [
            AppFeature.newProfileDesign.lookupKey: .bool(true)
        ]), priority: .lowest)
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

```swift
FeatureGate(AppFeature.newProfileDesign) {
    NewProfileView()
} fallback: {
    LegacyProfileView()
}

let url = service.stringValue(for: AppFeature.apiBaseUrl)
let retries = service.intValue(for: AppFeature.maxRetryCount)
```

### 3. Async remote provider

```swift
final class MyRemoteProvider: AsyncFeatureFlagProvider, Sendable {
    let name = "Remote"
    private let lock = OSAllocatedUnfairLock(initialState: [String: FeatureFlagValue]())

    func value(for key: String) -> FeatureFlagValue? {
        lock.withLock { $0[key] }
    }

    func fetchValues() async throws {
        // fetch + lock.withLock { $0 = mapped }
    }
}
```

### 4. Grouped keys

```swift
enum CheckoutFeature: String, FeatureFlagKey, GroupedFeatureFlag {
    case v2Flow
    var defaultValue: FeatureFlagValue { .bool(false) }
    static var group: FeatureFlagGroup { FeatureFlagGroup(prefix: "checkout") }
}

// lookupKey == "checkout.v2Flow" for providers, debug overrides, and rollouts
```

### 5. Rollouts

```swift
let rollout = RolloutProvider(userId: userId)
rollout.setRollout(for: AppFeature.newProfileDesign, percentage: 25)
// 0% returns .bool(false) (does not fall through); 100% returns .bool(true)
```

## Resolution order

Providers are sorted by priority (highest first). The first non-`nil` value wins; otherwise `defaultValue` is used. All mutable overrides use `lookupKey` (qualified for grouped flags).

## License

See repository license file.
