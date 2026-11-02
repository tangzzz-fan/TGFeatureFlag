import Testing
import Foundation
import os
@testable import TGFeatureFlagCore

/// A provider whose fetch takes a configurable amount of time.
final class SlowProvider: AsyncFeatureFlagProvider, Sendable {
    enum Failure: Error { case fetchFailed }

    let name: String
    private let delay: Duration
    private let shouldFail: Bool
    private let lock = OSAllocatedUnfairLock(initialState: [String: FeatureFlagValue]())

    init(name: String, delay: Duration, shouldFail: Bool = false) {
        self.name = name
        self.delay = delay
        self.shouldFail = shouldFail
    }

    func value(for key: String) -> FeatureFlagValue? {
        lock.withLock { $0[key] }
    }

    func fetchValues() async throws {
        try await Task.sleep(for: delay)
        if shouldFail { throw Failure.fetchFailed }
        lock.withLock { $0 = [BoolTestFeature.booleanFeature.lookupKey: .bool(true)] }
    }
}

@Suite("Refresh report")
struct RefreshReportTests {

    @Test("Providers refresh concurrently rather than one after another")
    func concurrentRefresh() async throws {
        let resolver = FeatureFlagResolver()
        for index in 0..<3 {
            resolver.register(
                provider: SlowProvider(name: "slow\(index)", delay: .milliseconds(100)),
                priority: .custom(index)
            )
        }

        let clock = ContinuousClock()
        let started = clock.now
        let report = try await resolver.refresh()
        let elapsed = clock.now - started

        #expect(report.isSuccess)
        #expect(report.outcomes.count == 3)
        // Sequential would be ~300 ms. Leave headroom for slow CI machines.
        #expect(elapsed < .milliseconds(250), "refresh took \(elapsed), providers did not run concurrently")
    }

    @Test("A provider that exceeds the timeout does not block the others")
    func timeoutIsolation() async throws {
        let resolver = FeatureFlagResolver()
        resolver.register(provider: SlowProvider(name: "hanging", delay: .seconds(5)), priority: .highest)
        resolver.register(
            provider: SlowProvider(name: "healthy", delay: .milliseconds(10)),
            priority: .lowest
        )

        let clock = ContinuousClock()
        let started = clock.now
        let report = try await resolver.refresh(timeout: .milliseconds(100))
        let elapsed = clock.now - started

        #expect(report.outcomes.count == 2)
        #expect(report.outcomes[0].providerName == "hanging")
        #expect(report.outcomes[0].result == .timedOut)
        #expect(report.outcomes[1].result == .refreshed)
        #expect(report.failures == 1)
        #expect(report.hasAnyFreshValue)
        #expect(elapsed < .seconds(2), "the timeout should have cut the hanging provider short")
    }

    @Test("Report keeps registration order regardless of completion order")
    func registrationOrderPreserved() async throws {
        let resolver = FeatureFlagResolver()
        resolver.register(provider: SlowProvider(name: "first", delay: .milliseconds(80)), priority: .highest)
        resolver.register(provider: SlowProvider(name: "second", delay: .milliseconds(40)), priority: .custom(50))
        resolver.register(provider: SlowProvider(name: "third", delay: .milliseconds(10)), priority: .lowest)

        let report = try await resolver.refresh()

        #expect(report.outcomes.map(\.providerName) == ["first", "second", "third"])
    }

    @Test("Provider failures are reported, not thrown")
    func failureReported() async throws {
        let resolver = FeatureFlagResolver()
        resolver.register(provider: SlowProvider(name: "broken", delay: .zero, shouldFail: true), priority: .highest)

        let report = try await resolver.refresh()

        #expect(report.failures == 1)
        guard case .failed(let message) = report.outcomes[0].result else {
            Issue.record("expected a failed outcome, got \(report.outcomes[0].result)")
            return
        }
        #expect(message.contains("fetchFailed"))
    }

    @Test("Cancelling the caller propagates CancellationError")
    func cancellationPropagates() async {
        let resolver = FeatureFlagResolver()
        resolver.register(provider: SlowProvider(name: "slow", delay: .seconds(5)), priority: .highest)

        let task = Task { try await resolver.refresh(timeout: .seconds(30)) }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("No async providers yields an empty successful report")
    func noAsyncProviders() async throws {
        let resolver = FeatureFlagResolver()
        resolver.register(provider: LocalProvider(flags: [:]), priority: .highest)

        let report = try await resolver.refresh()

        #expect(report.outcomes.isEmpty)
        #expect(report.isSuccess)
    }
}
