---
kind: logging_system
name: FeatureFlagLogger diagnostic protocol
category: logging_system
scope:
    - '**'
---

The repository implements a lightweight diagnostic logging system via the `FeatureFlagLogger` protocol (defined in `FeatureFlagService.swift`). Consumers implement this protocol and attach it via `service.setLogger(_:)` to observe which provider resolved each flag. The logger is called on every resolution event with the flag key, the resolving provider's name (or `nil` for default fallback), and the resolved value. It is also invoked during `refresh()` for async provider fetch results. The codebase does not use Foundation.Logger, os.log, or print/NSLog statements; all logging is opt-in through the protocol hook.