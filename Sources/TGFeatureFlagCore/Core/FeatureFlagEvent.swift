import Foundation
import os

/// Something worth reporting about feature-flag resolution.
///
/// The previous interface was `log(flag:resolvedBy:value:)`, which had nowhere to put a refresh
/// failure, so refresh outcomes were smuggled through as `flag: "*"` with the error text inside
/// the `value` field. That made the data unusable: you could not tell an event about a flag from
/// an event about a provider, and the error lived in a field typed as a flag value.
public enum FeatureFlagEvent: Sendable, Equatable {
    /// A flag was resolved. Fires on every read, so it is off by default.
    case resolved(flag: String, provider: String?, value: FeatureFlagValue)

    /// A flag was shown to this session for the first time with this value.
    ///
    /// Deduplicated per flag and value, which is what makes the stream usable for A/B analysis:
    /// a view that reads a flag on every frame must not look like thousands of users.
    case exposure(flag: String, value: FeatureFlagValue)

    /// A provider returned a value whose case does not match the key's declared type.
    case typeMismatch(flag: String, expected: String, actual: FeatureFlagValue)

    /// A provider refreshed successfully.
    case refreshed(provider: String, duration: Duration)

    /// A provider threw while refreshing.
    case refreshFailed(provider: String, reason: String)

    /// A provider did not finish within the refresh timeout.
    case refreshTimedOut(provider: String)
}

/// Receives feature-flag events.
///
/// Called synchronously on whichever thread resolved the flag, so implementations must be fast
/// and must not call back into the resolver. Buffer or forward to another queue rather than doing
/// I/O here.
public protocol FeatureFlagEventSink: Sendable {
    func receive(_ event: FeatureFlagEvent)
}

/// Which events to emit.
///
/// `.resolutions` is excluded from `standard` on purpose: it fires on every read, which is fine
/// for a debug session and wasteful in production.
public struct FeatureFlagEventOptions: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// One event per flag and value per session.
    public static let exposures = FeatureFlagEventOptions(rawValue: 1 << 0)

    /// Every resolution. Verbose; intended for debugging.
    public static let resolutions = FeatureFlagEventOptions(rawValue: 1 << 1)

    /// Provider refresh outcomes.
    public static let refresh = FeatureFlagEventOptions(rawValue: 1 << 2)

    /// Values whose case does not match the key's declared type.
    public static let typeMismatches = FeatureFlagEventOptions(rawValue: 1 << 3)

    /// Exposures, refresh outcomes and type mismatches.
    public static let standard: FeatureFlagEventOptions = [.exposures, .refresh, .typeMismatches]

    /// Everything, including a per-read resolution event.
    public static let all: FeatureFlagEventOptions = [.exposures, .resolutions, .refresh, .typeMismatches]
}

/// Remembers which flag/value pairs have already been reported this session.
final class FeatureFlagExposureLog: Sendable {
    private struct Key: Hashable, Sendable {
        let flag: String
        let value: FeatureFlagValue
    }

    private let seen = OSAllocatedUnfairLock(initialState: Set<Key>())

    /// - Returns: `true` the first time a pair is seen.
    func record(flag: String, value: FeatureFlagValue) -> Bool {
        seen.withLock { $0.insert(Key(flag: flag, value: value)).inserted }
    }

    func reset() {
        seen.withLock { $0.removeAll() }
    }
}

/// Fan-out point for events, passed down to the resolution helpers.
///
/// Optional everywhere so that a resolver with no sink pays nothing: no allocation, no branch on
/// the hot path beyond a single nil check.
struct FeatureFlagEventEmitter: Sendable {
    let sink: any FeatureFlagEventSink
    let options: FeatureFlagEventOptions
    let exposures = FeatureFlagExposureLog()

    func resolved(flag: String, provider: String?, value: FeatureFlagValue) {
        guard options.contains(.resolutions) else { return }
        sink.receive(.resolved(flag: flag, provider: provider, value: value))
    }

    func exposure(flag: String, value: FeatureFlagValue) {
        guard options.contains(.exposures) else { return }
        guard exposures.record(flag: flag, value: value) else { return }
        sink.receive(.exposure(flag: flag, value: value))
    }

    func typeMismatch(flag: String, expected: String, actual: FeatureFlagValue) {
        guard options.contains(.typeMismatches) else { return }
        sink.receive(.typeMismatch(flag: flag, expected: expected, actual: actual))
    }

    func refreshed(provider: String, duration: Duration) {
        guard options.contains(.refresh) else { return }
        sink.receive(.refreshed(provider: provider, duration: duration))
    }

    func refreshFailed(provider: String, reason: String) {
        guard options.contains(.refresh) else { return }
        sink.receive(.refreshFailed(provider: provider, reason: reason))
    }

    func refreshTimedOut(provider: String) {
        guard options.contains(.refresh) else { return }
        sink.receive(.refreshTimedOut(provider: provider))
    }

    func startNewSession() {
        exposures.reset()
    }
}
