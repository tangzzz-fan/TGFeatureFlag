import Foundation
import Observation
import TGFeatureFlag

/// Collects library events so the demo can show what a production sink would forward to
/// analytics.
///
/// This is the piece that replaces the old `FeatureFlagLogger`: instead of a formatted
/// string, the app receives typed cases it can switch on.
@MainActor
@Observable
final class DemoEventLog {
    struct Entry: Identifiable {
        let id = UUID()
        let symbol: String
        let text: String
    }

    private(set) var entries: [Entry] = []
    private(set) var exposureCount = 0
    private(set) var refreshCount = 0
    private(set) var mismatchCount = 0

    /// Keep the list short enough to stay readable on one screen.
    private let capacity = 30

    func record(_ event: FeatureFlagEvent) {
        switch event {
        case .exposure(let flag, let value):
            exposureCount += 1
            append("eye", "exposure  \(flag) = \(value.demoText)")

        case .resolved:
            // Only emitted when `.resolutions` is enabled; too noisy for `.standard`.
            break

        case .typeMismatch(let flag, let expected, let actual):
            mismatchCount += 1
            append(
                "exclamationmark.triangle",
                "mismatch  \(flag) expected \(expected), got \(actual.demoText)"
            )

        case .valueWidened(let flag, let expected, let actual):
            mismatchCount += 1
            append(
                "arrow.left.arrow.right",
                "widened  \(flag) expected \(expected), widened \(actual.demoText)"
            )

        case .refreshed(let provider, let duration):
            refreshCount += 1
            append("checkmark.circle", "refreshed  \(provider) in \(duration.demoMilliseconds)")

        case .refreshFailed(let provider, let reason):
            refreshCount += 1
            append("xmark.circle", "failed  \(provider) — \(reason)")

        case .refreshTimedOut(let provider):
            refreshCount += 1
            append("clock.badge.exclamationmark", "timeout  \(provider)")
        }
    }

    /// Clears the log and the counters, mirroring what `startNewSession()` does to exposures.
    func reset() {
        entries.removeAll()
        exposureCount = 0
        refreshCount = 0
        mismatchCount = 0
    }

    private func append(_ symbol: String, _ text: String) {
        entries.insert(Entry(symbol: symbol, text: text), at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }
}

/// `FeatureFlagEventSink` receives events synchronously on whichever thread resolved the
/// flag, so the sink itself must be `Sendable` and must not block. This one forwards to the
/// main actor, which is what a real analytics sink would do with its own queue.
struct DemoEventSink: FeatureFlagEventSink {
    let log: DemoEventLog

    func receive(_ event: FeatureFlagEvent) {
        Task { @MainActor in
            log.record(event)
        }
    }
}

extension FeatureFlagValue {
    /// Readable form for the demo's event log and rows.
    var demoText: String {
        switch self {
        case .bool(let value): return value ? "true" : "false"
        case .string(let value): return "\"\(value)\""
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        }
    }
}

extension Duration {
    var demoMilliseconds: String {
        let parts = components
        let milliseconds = parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000
        return "\(milliseconds) ms"
    }
}
