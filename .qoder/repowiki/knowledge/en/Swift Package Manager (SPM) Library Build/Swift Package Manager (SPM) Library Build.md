---
kind: build_system
name: Swift Package Manager (SPM) Library Build
category: build_system
scope:
    - '**'
source_files:
    - Package.swift
    - .gitignore
---

This repository is a pure Swift Package with no custom build scripts, CI pipelines, Dockerfiles, or Makefiles. The entire build system is defined by the single `Package.swift` manifest and relies on Swift Package Manager conventions.

**Build toolchain & platforms**
- Declares `swift-tools-version: 6.0`, requiring Xcode 15+ / Swift 6 toolchain.
- Targets iOS 17+ and macOS 14+ via the `platforms` array — these are the only supported deployment targets.

**Products & targets**
- One library product `TGFeatureFlag` exposing the module `TGFeatureFlag`.
- One test target `TGFeatureFlagTests` depending on the library.
- No separate targets per subdirectory (`Core/`, `Providers/`, `SwiftUI/`) — everything compiles into a single module; source layout under `Sources/TGFeatureFlag/` is purely organizational.

**Dependency management**
- Zero external dependencies declared in `Package.swift`; the package depends only on the standard library and SwiftUI (implicitly available on the declared platforms).
- Example app under `Example/TGFeatureFlagDemo/` is an independent Xcode project that consumes the package locally via path dependency; it is not part of the SPM graph.

**Testing**
- Tests live in `Tests/TGFeatureFlagTests/` and are invoked through SPM (`swift test`). There is no custom test harness or parallelism configuration.

**Artifacts & distribution**
- Distribution is via the Swift Package Index (no `.gitignore` entries for archives, wheels, or frameworks). Versioning follows conventional tags referenced from `CHANGELOG.md`.
- The `.build/` directory is gitignored as the default SPM build cache.

**Conventions developers should follow**
- Add new source files directly under `Sources/TGFeatureFlag/`; there is no per-directory target wiring to update.
- Keep platform constraints aligned with the `platforms` declaration in `Package.swift`.
- External dependencies must be added in `Package.swift` `dependencies` and re-exported if needed by consumers.