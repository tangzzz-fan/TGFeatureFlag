# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
