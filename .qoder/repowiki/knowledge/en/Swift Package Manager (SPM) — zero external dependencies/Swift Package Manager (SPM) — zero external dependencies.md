---
kind: dependency_management
name: Swift Package Manager (SPM) — zero external dependencies
category: dependency_management
scope:
    - '**'
source_files:
    - Package.swift
---

This repository is a Swift Package that declares **no third-party dependencies**. All runtime imports are satisfied by Apple's platform SDKs (`Foundation`, `Observation`, `Combine`, `SwiftUI`), and the package manifest itself lists no `.package()` entries. Consumers add it via SPM using the GitHub URL shown in README.md.

Key files and conventions:
- `Package.swift` — single-package manifest declaring one library product (`TGFeatureFlag`) and one test target; minimum platforms are iOS 17 and macOS 14, which also constrain the available stdlib modules.
- No lockfile (`Package.resolved`) or vendored directory exists in the repo, so dependency resolution is left to each consumer's Xcode/SPM toolchain.
- The demo app under `Example/TGFeatureFlagDemo/` is an Xcode project (`.xcodeproj`) rather than an SPM target, so its own dependency wiring lives outside this package's scope.

Rules for developers:
- Do not introduce new external packages without adding them to `Package.swift`; keep the library free of non-Apple dependencies as it currently is.
- When bumping the minimum supported OS version, update the `platforms` array in `Package.swift` accordingly.