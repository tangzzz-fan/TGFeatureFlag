---
kind: configuration_system
name: Feature Flag Configuration System
category: configuration_system
scope:
    - '**'
source_files:
    - Sources/TGFeatureFlag/Core/FeatureFlagKey.swift
    - Sources/TGFeatureFlag/Core/FeatureFlagProvider.swift
    - Sources/TGFeatureFlag/Core/FeatureFlagService.swift
    - Sources/TGFeatureFlag/Providers/DebugProvider.swift
    - Sources/TGFeatureFlag/Providers/LocalProvider.swift
    - Sources/TGFeatureFlag/Providers/UserDefaultsProvider.swift
    - Sources/TGFeatureFlag/SwiftUI/FeatureGate.swift
    - Example/TGFeatureFlagDemo/TGFeatureFlagDemo/MockRemoteProvider.swift
    - Example/TGFeatureFlagDemo/TGFeatureFlagDemo/TGFeatureFlagDemoApp.swift
---

TGFeatureFlag implements a pluggable, chain-of-responsibility configuration system for feature flags and runtime app configuration on iOS/macOS. The system centers around three core abstractions plus several concrete providers that are registered into an `@Observable` service which drives SwiftUI reactivity.

**Core Abstractions**
- `FeatureFlagKey` — a `RawRepresentable` (String) protocol that defines each flag's raw key, its default value (`Any`), and an optional human-readable description. Consumers typically implement this as an enum with a `switch` returning the per-case default.
- `FeatureFlagProvider` — a `Sendable` protocol exposing `name: String` and `value(for: String) -> Any?`. Each provider is a source of truth for one or more keys.
- `FeatureFlagService` — an `@Observable` class that holds an ordered list of providers and resolves values by iterating the chain until a provider returns non-nil, then falling back to the key's `defaultValue`. It exposes `isEnabled(_:)` for booleans and a generic `value<T>(for:)` accessor that casts at runtime, crashing in debug on type mismatch.

**Provider Chain & Priority**
Providers are registered via `register(provider:prioriy:)` where `.highest` inserts at index 0 and `.lowest` appends. Resolution order is first-to-last, so higher-priority providers shadow lower ones. The demo wires the chain as:
1. `DebugProvider` (highest) — mutable in-memory overrides, thread-safe via `NSLock`, supports `setOverride(for:value:)` and `reset()`.
2. `MockRemoteProvider` (demo only) — simulates a remote config fetch; replace with a real network-backed provider.
3. `UserDefaultsProvider` — reads from `UserDefaults.standard`; observes `UserDefaults.didChangeNotification` and calls `service.triggerUpdate()` to propagate changes.
4. `LocalProvider` (lowest) — static in-memory dictionary, optionally constructed from an array of enabled `FeatureFlagKey`s.

**SwiftUI Integration**
The service is injected into the SwiftUI environment via `.featureFlagService(service)` and consumed through `@Environment(FeatureFlagService.self)`. `FeatureGate<F,Content,Fallback>` is a conditional view that renders `content` when `service.isEnabled(feature)` is true and `fallback` otherwise; it automatically recomposes when the underlying provider chain changes because `FeatureFlagService` is `@Observable`.

**Runtime Update Mechanism**
- `UserDefaultsProvider` posts `UserDefaults.didChangeNotification`; `FeatureFlagService` listens in its initializer and increments an internal `_updateTrigger` counter, which SwiftUI's Observation framework treats as a dependency change.
- `DebugProvider` updates are immediate since they mutate the in-memory store directly.
- A custom remote provider should call `service.triggerUpdate()` after applying new values so dependent views refresh.

**Type Safety & Defaults**
Flags are declared as enums conforming to `FeatureFlagKey`, giving compile-time awareness of every flag and its default. The generic `value<T>(for:)` performs a runtime cast against the stored `Any`; if the requested type differs from the default's type, a `fatalError` fires in debug builds. This keeps defaults centralized while allowing heterogeneous types (Bool, String, Int, Double).

**Conventions for consumers**
- Define all flags in a single `enum ... : FeatureFlagKey, CaseIterable` with explicit raw string keys and a `switch` defaulting each case.
- Register providers at app launch in descending precedence order; keep `DebugProvider` highest so developer overrides always win.
- For persistent user preferences, use `UserDefaultsProvider` with a dedicated `UserDefaults(suiteName:)` if you need cross-app sharing.
- Replace `MockRemoteProvider` with a real implementation that fetches JSON/protobuf from your backend and calls `service.triggerUpdate()` on completion.
- Use `FeatureGate` for UI branching; prefer `service.isEnabled(_:)` / `service.value(for:)` in non-SwiftUI code.