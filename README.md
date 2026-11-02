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
- **Typed keys**: `TypedFeatureFlag` makes reads return the declared Swift type, and `isEnabled` only accepts `Bool` keys.
- **Sendable Resolver**: build cold `FeatureFlagSnapshot` values for Redux middleware.
- **Priority chain**: `.highest` / `.lowest` / `.custom(Int)`.
- **Async providers**: `AsyncFeatureFlagProvider` + `refresh()`. Providers refresh concurrently, each with its own timeout, and the call returns a per-provider report.
- **Rollouts**: stable FNV-1a hashing (process-independent), configurable in code or from a remote payload.
- **Cold start**: `LastKnownGoodStore` persists the last good snapshot so launch renders real values instead of defaults.
- **Change notification**: providers publish their own changes, so the UI updates without manual triggers.
- **Observability**: typed events, with exposure events deduplicated per session.
- **Grouping**: `FeatureFlagGroup` / `GroupedFeatureFlag` with unified `lookupKey`.
- **SwiftUI**: one `FeatureGate` that takes either an injected snapshot or the environment service.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/tangzzz-fan/TGFeatureFlag.git", from: "0.5.0")
]
```

The package ships three products:

| Product | Contents | Use when |
|---|---|---|
| `TGFeatureFlag` | Everything, re-exported | You just want `import TGFeatureFlag` |
| `TGFeatureFlagCore` | Resolution, providers, snapshots — no SwiftUI | Background agents, extensions, pure logic modules |
| `TGFeatureFlagSwiftUI` | Gates and the debug screen | You want the dependency to be explicit |

`TGFeatureFlagCore` has no SwiftUI dependency, so linking the core half does not pull view code into an app extension or a background target.

## Continuous Integration

GitHub Actions runs `swift build` and `swift test` for pushes and PRs targeting `main`.

## Usage

### 1. Define Feature Flags

One value type per enum, because `TypedFeatureFlag.Value` is an associated type. Boolean switches and configuration values live in separate enums:

```swift
import TGFeatureFlag

enum AppFeature: String, TypedFeatureFlag, CaseIterable {
    case newProfileDesign = "feature_new_profile"
    case maxRetryCount = "config_retry_count"

    var typedDefaultValue: Bool {
        switch self {
        case .newProfileDesign: return false
        case .maxRetryCount: return true
        }
    }
}

enum AppConfig: String, TypedFeatureFlag, CaseIterable {
    case apiBaseUrl = "config_api_base_url"

    var typedDefaultValue: String { "https://api.production.com" }
}
```

Reads are typed, so there is nothing to unwrap:

```swift
let enabled: Bool = resolver.isEnabled(AppFeature.newProfileDesign)
let url: String = resolver.value(for: AppConfig.apiBaseUrl)
```

`isEnabled` only accepts keys whose value type is `Bool`, so asking a string flag whether it is "enabled" is a compile error rather than a silent fallback. `rawValue(for:)` is the untyped escape hatch for tooling.

### 2a. Redux path — Resolver + Snapshot

```swift
let resolver = FeatureFlagResolver()
resolver.register(provider: DebugProvider(), priority: .highest)
resolver.register(provider: MyRemoteProvider(), priority: .custom(80))
resolver.register(provider: LocalProvider(flags: [:]), priority: .lowest)

_ = try await resolver.refresh()
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
FeatureGate(AppFeature.newProfileDesign, snapshot: storeState.flags) {
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

let url = service.value(for: AppConfig.apiBaseUrl)
let enabled = service.isEnabled(AppFeature.newProfileDesign)
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

Providers refresh concurrently, so three 100 ms sources cost roughly 100 ms rather than 300 ms. Each provider gets its own timeout, and one hanging source cannot delay the rest:

```swift
let report = try await resolver.refresh(timeout: .seconds(10))

if report.isSuccess {
    // every provider refreshed
} else {
    for outcome in report.outcomes where !outcome.didRefresh {
        // outcome.providerName + outcome.result tells you which source failed and how
    }
}
```

Provider failures come back in the report rather than being thrown, so one broken source never prevents the others from refreshing. Only cancellation is thrown, because that belongs to the caller.

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

Percentages configured in code still need a release to change, which defeats the point. To drive them from a backend, use `RemoteRolloutProvider` and push the document:

```swift
let remote = RemoteRolloutProvider(userId: userId)
resolver.register(provider: remote, priority: .custom(80))

// Later, whenever the payload arrives:
try remote.apply(json: payload)   // operators moving 5% → 50% no longer ship a build
```

```json
{
  "rollouts": {
    "checkout.v2_flow": { "percentage": 25 },
    "config_banner_text": { "percentage": 50, "value": "Try the new checkout" }
  }
}
```

`value` accepts a bare literal (`true`, `3`, `"text"`, `1.5`) so the document is writable by hand. Applying a document replaces the whole rollout set — a flag that disappears from the payload stops rolling out instead of keeping its last percentage. Malformed entries are skipped and listed in `ignoredKeys` rather than failing the entire document.

Changing the percentage at runtime republishes a change, so the UI updates without a restart. Changing `userId` re-buckets.

### 6. Cold start without a flash

By default every launch starts from `defaultValue` and jumps to the remote values once a refresh lands, so users watch the interface change under them. Persist the last good snapshot and prime the chain from disk:

```swift
let store = LastKnownGoodStore(namespace: "app")

// Launch, before any network call:
if let cached = store.load() {
    resolver.register(
        provider: CachedSnapshotProvider(snapshot: cached),
        priority: .custom(10)   // below remote, above local defaults
    )
}

// After a refresh succeeds:
try? store.save(resolver.snapshot(for: AppFeature.allCases))
```

`load()` never throws: a missing, truncated, or unrecognised file returns `nil`, so a bad cache degrades to defaults instead of failing the launch. Writes are atomic, so an interrupted write cannot leave a half file behind.

### 7. Events and exposures

```swift
final class MySink: FeatureFlagEventSink {
    func receive(_ event: FeatureFlagEvent) {
        switch event {
        case .exposure(let flag, let value):
            analytics.recordExposure(flag: flag, value: value)
        case .typeMismatch(let flag, let expected, let actual):
            logger.warning("flag \(flag) expected \(expected), got \(actual)")
        case .refreshFailed(let provider, let reason):
            logger.warning("\(provider) failed: \(reason)")
        case .refreshTimedOut(let provider):
            logger.warning("\(provider) timed out")
        case .refreshed:
            break
        case .resolved:
            break   // per-read; only emitted when .resolutions is enabled
        }
    }
}

resolver.setEventSink(MySink())                       // .standard: exposures, refresh, mismatches
resolver.setEventSink(MySink(), options: .all)        // adds a per-read .resolved event
```

Exposures are deduplicated per flag and value, so a view that reads a flag on every frame still reports one exposure. Call `startNewSession()` at a session boundary to report them again.

`.resolutions` is excluded from `.standard` on purpose: it fires on every read. Everything else is cheap enough to leave on in production.

## Resolution order

Providers are sorted by priority (highest first). The first non-`nil` value wins; otherwise `defaultValue` is used. All mutable overrides use `lookupKey` (qualified for grouped flags).

**Ties:** when two providers share the same priority, the **first registered** one wins. Registration order only breaks ties — it never overrides priority. This is covered by tests, so reordering the insert logic can't silently change resolution.

## Snapshot JSON format

`FeatureFlagSnapshot` and `FeatureFlagValue` encode to an explicit, tagged shape:

```json
{
  "values": {
    "feature_new_home": { "type": "bool", "value": true },
    "config_retry_count": { "type": "int", "value": 3 }
  }
}
```

The type tag is deliberate, not incidental. An untagged `{"value": true}` form would be ambiguous on the way back: JSON `1` decodes as an integer, so `.double(1.0)` would silently round-trip into `.int(1)`. The tag keeps the round trip lossless and is simple enough for a backend to produce by hand. Unknown tags fail decoding with a descriptive error rather than falling back to a default.

Snapshots are immutable once built — `values` is read-only, so a dispatched snapshot cannot drift underneath the Store.

## License

See repository license file.
