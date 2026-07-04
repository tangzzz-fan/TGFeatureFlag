---
kind: error_handling
name: Fatal-only type-mismatch handling with no error propagation
category: error_handling
scope:
    - '**'
source_files:
    - Sources/TGFeatureFlag/Core/FeatureFlagService.swift
---

This repository does not implement a structured error-handling system. The TGFeatureFlag framework is intentionally lightweight and avoids throwing errors or returning Result types across its public API.

**What the codebase does**
- All provider lookups (`FeatureFlagProvider.value(for:)`) return `Any?`, and `FeatureFlagService.value<T>(for:)` returns `T` directly — callers never see an error value.
- The only failure path is in `FeatureFlagService.value<T>`: when no provider supplies a value and the flag's default cannot be cast to the requested generic type `T`, the service calls `fatalError(...)` (line 78 of `Core/FeatureFlagService.swift`). This is treated as a programming mistake (a developer-defined key whose default type mismatches the call site) rather than a recoverable runtime condition.

**What the codebase does not do**
- No custom `Error` enum, sentinel values, or `Result`/`throws` usage anywhere in `Sources/`.
- No middleware, logging, or user-facing error presentation layer.
- No `do/catch` blocks; tests assert success paths via `#expect` and never exercise error conditions.

**Conventions developers should follow**
- Treat any mismatch between a `FeatureFlagKey.defaultValue` and the requested generic type at a call site as a development-time bug that will crash the app; fix the key's default or the call-site type instead of catching an error.
- Do not attempt to wrap feature-flag reads in `do/catch`; the API is designed to be infallible from the caller's perspective.