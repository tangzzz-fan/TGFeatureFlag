# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-07-04

### Added
- **tvOS and watchOS Support**: Added `.tvOS(.v17)` and `.watchOS(.v10)` platform targets.
- **RolloutProvider**: New provider enabling percentage-based feature flag rollouts. Uses deterministic hashing of a user identifier to ensure consistent results per user. Supports custom rollout values and per-flag configuration.
- **FeatureFlagGroup & GroupedFeatureFlag Protocol**: Namespace support for organizing feature flags into logical groups. Grouped flags automatically use qualified keys (e.g., `"ui.newDesign"`) for provider lookups.
- **Grouped Flag Tests**: Added 9 new tests covering rollout percentages (0%, 50%, 100%), deterministic hashing, custom rollout values, qualified keys, custom separators, and fallback behavior.

### Changed
- **FeatureFlagService Key Resolution**: `value(for:)` now resolves qualified keys for flags conforming to `GroupedFeatureFlag`, enabling seamless group-based provider lookups.

## [0.3.0] - 2026-07-04

### Added
- **AsyncFeatureFlagProvider Protocol**: New protocol for providers that fetch values asynchronously (e.g., Firebase Remote Config, LaunchDarkly). Async providers cache values locally and expose them via the synchronous `value(for:)` method.
- **FeatureFlagService.refresh()**: Async method that triggers `fetchValues()` on all registered `AsyncFeatureFlagProvider` instances. Returns the number of providers that failed to refresh. Automatically triggers UI update after refresh.
- **Async Provider Tests**: Added 3 new tests for async refresh, failure handling, and mixed sync/async provider chains.

### Changed
- **Demo App**: `MockRemoteProvider` now implements `AsyncFeatureFlagProvider`. Settings view uses `await service.refresh()` instead of callback-based API.

## [0.2.0] - 2026-07-04

### Added
- **Numeric Priority System**: `Priority.custom(Int)` allows fine-grained provider ordering. Higher values = higher priority. Providers are automatically sorted by priority level.
- **FeatureFlagLogger Protocol**: New `FeatureFlagLogger` protocol enables observing which provider resolved each flag, useful for production debugging. Use `service.setLogger(_:)` to install.
- **Provider Fault Tolerance**: Provider value lookups are now guarded; a failing provider will be skipped and the next provider in the chain will be tried.
- **Expanded Test Coverage**: Added 8 new tests covering custom priority, mixed priority levels, empty provider chain, `DebugProvider.reset()`, `provider(ofType:)` lookup, logger resolution, and `LocalProvider(enabledFeatures:)` initializer.

### Changed
- **Internal Provider Storage**: Providers are now stored as sorted entries with their priority level, enabling correct insertion order for custom priorities.

## [0.1.0] - 2026-07-04

### Added
- **Int/Double Editors in Debug View**: `FeatureFlagDebugView` now supports editing `Int` values via `Stepper` and `Double` values via numeric `TextField`.
- **Swift 6 Concurrency Safety**: Added `@MainActor` annotation to `FeatureFlagService` for safe use with Swift 6 strict concurrency.

### Changed
- **FeatureGate Lazy Construction**: `FeatureGate` now stores `@ViewBuilder` closures instead of eagerly evaluated views, ensuring only the active branch is constructed.
- **UserDefaultsProvider Documentation**: Added thread-safety note explaining why `@unchecked Sendable` is appropriate.

### Fixed
- Removed unused `Combine` import in `UserDefaultsProvider.swift`.
- Fixed `FeatureGate` eager view construction that could cause unnecessary view instantiation.

## [0.0.1] - 2026-01-18

### Added
- **Non-Boolean Value Support**: Feature flags now support `String`, `Int`, `Double`, and other types in addition to `Bool`.
- **Generic Value Retrieval**: Added `value(for:)` method to `FeatureFlagService` for type-safe value access.
- **Demo App Enhancements**:
  - Added "Checkout V2" flow demonstration with visual feedback.
  - Added "Product Detail" page showing conditional navigation and layout adaptation.
  - Added "API Base URL" configuration example.
- **Documentation**: Added English `README.md` and updated Chinese architecture design document.

### Changed
- **Architecture**: Refactored `FeatureFlagKey` and `FeatureFlagProvider` protocols to support `Any` type values.
- **Testing**: Migrated test suite from XCTest to Swift Testing framework.
- **Thread Safety**: Improved thread safety in `LocalProvider` and `MockRemoteProvider` using `Sendable` conformance.
- **Debug View**: Updated `FeatureFlagDebugView` to support editing String values.

### Fixed
- Fixed generic parameter inference issues in SwiftUI views.
- Fixed layout occlusion issues in Product Detail page when navigation bar is hidden.
