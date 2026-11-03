import Foundation
import Observation
import TGFeatureFlag

/// Owns the object graph the demo shows off: the provider chain, the last-known-good cache
/// and the event log.
///
/// The ordering of the `register` calls below is the actual lesson — it is the resolution
/// order, highest priority first:
///
///     1. DebugProvider          .highest    developer overrides win over everything
///     2. RemoteRolloutProvider  .custom(80)  percentage rollouts from a pushed document
///     3. MockRemoteProvider     .custom(60)  fetched config
///     4. FlakyProvider          .custom(50)  always fails; proves partial refresh
///     5. CachedSnapshotProvider .custom(40)  last-known-good from disk (cold start only)
///     6. UserDefaultsProvider   .custom(20)  external overrides
///     7. LocalProvider          .lowest      shipped defaults
@MainActor
@Observable
final class DemoWiring {
    /// Two identities whose buckets differ, so switching actually changes an assignment.
    /// `demo-user-001` lands inside a 50% rollout of `checkout.v2_flow`; `demo-user-003`
    /// lands outside it.
    static let userIds = ["demo-user-001", "demo-user-003"]

    /// Percentages the "ops console" can push, as a real backend document would.
    static let percentagePresets = [0, 5, 50, 100]

    let service: FeatureFlagService
    let eventLog: DemoEventLog
    let cacheStore: LastKnownGoodStore
    let remoteRollout: RemoteRolloutProvider

    /// Whether the chain was primed from the on-disk cache at launch.
    let primedFromCache: Bool
    let primedValueCount: Int

    /// What the ops console last pushed. Tracked here so the UI can show intent next to the
    /// resolved values.
    private(set) var pushedPercentage: Int?

    private(set) var activeUserId: String

    /// Result of the last manual cache operation, shown instead of the launch state.
    private(set) var cacheActionStatus: String?

    init() {
        let log = DemoEventLog()
        let store = LastKnownGoodStore(namespace: "tgfeatureflag-demo")
        let cached = store.load()

        let service = FeatureFlagService(observeUserDefaults: true)

        // `.standard` = exposures, refresh outcomes and type mismatches. `.all` would add a
        // per-read `.resolved` event, which is useful while debugging and far too noisy
        // otherwise.
        service.setEventSink(DemoEventSink(log: log), options: .standard)

        service.register(provider: DebugProvider(), priority: .highest)

        let rollout = RemoteRolloutProvider(userId: Self.userIds[0])
        service.register(provider: rollout, priority: .custom(80))

        service.register(provider: MockRemoteProvider(), priority: .custom(60))
        service.register(provider: FlakyProvider(), priority: .custom(50))

        // The cold-start cache sits below the network sources and above the shipped
        // defaults: cached values are better than defaults, worse than anything fetched
        // this session.
        if let cached {
            service.register(
                provider: CachedSnapshotProvider(snapshot: cached),
                priority: .custom(40)
            )
        }

        service.register(provider: UserDefaultsProvider(), priority: .custom(20))
        service.register(provider: LocalProvider(flags: Self.localFlags), priority: .lowest)

        self.service = service
        self.eventLog = log
        self.cacheStore = store
        self.remoteRollout = rollout
        self.primedFromCache = cached != nil
        self.primedValueCount = cached?.values.count ?? 0
        self.activeUserId = Self.userIds[0]

        // Start with a document already applied, so the rollout section is not empty.
        pushRollouts(all: 50)
    }

    // MARK: - Rollouts

    /// Applies a rollout document covering every checkout flag, as ops would after editing a
    /// dashboard.
    func pushRollouts(all percentage: Int) {
        let rollouts = CheckoutFeature.allCases.reduce(
            into: [String: RolloutConfiguration.Entry]()
        ) { result, feature in
            result[feature.lookupKey] = RolloutConfiguration.Entry(percentage: percentage)
        }

        // Replaces the whole set — a flag missing from the document stops rolling out
        // instead of keeping its previous percentage.
        remoteRollout.apply(RolloutConfiguration(rollouts: rollouts))
        pushedPercentage = percentage
    }

    /// Removes every rollout, so the flags fall through to the providers below.
    func clearRollouts() {
        remoteRollout.clear()
        pushedPercentage = nil
    }

    /// Switches identity. Buckets are derived from `userId` + flag key, so this re-assigns
    /// every rollout without any document changing.
    func switchUser(to userId: String) {
        guard userId != activeUserId else { return }
        remoteRollout.userId = userId
        activeUserId = userId
    }

    // MARK: - Cold start cache

    /// The union of every key the demo knows about.
    ///
    /// `snapshot(for:)` takes a homogeneous sequence, so the three key enums are merged by
    /// hand. A real app usually has one enum per area and saves them separately.
    var currentSnapshot: FeatureFlagSnapshot {
        var values: [String: FeatureFlagValue] = [:]
        values.merge(service.snapshot(for: DemoFeature.allCases).values) { _, new in new }
        values.merge(service.snapshot(for: DemoConfig.allCases).values) { _, new in new }
        values.merge(service.snapshot(for: CheckoutFeature.allCases).values) { _, new in new }
        return FeatureFlagSnapshot(values: values)
    }

    func saveLastKnownGood() {
        do {
            try cacheStore.save(currentSnapshot)
            cacheActionStatus = "saved \(currentSnapshot.values.count) values"
        } catch {
            cacheActionStatus = "save failed: \(error)"
        }
    }

    func clearLastKnownGood() {
        do {
            try cacheStore.clear()
            cacheActionStatus = "cleared — next launch starts from defaults"
        } catch {
            cacheActionStatus = "clear failed: \(error)"
        }
    }

    // MARK: - Local defaults

    static var localFlags: [String: FeatureFlagValue] {
        [
            DemoFeature.newHomeDesign.lookupKey: .bool(true),
            DemoFeature.experimentalCheckout.lookupKey: .bool(false),

            // Deliberately the wrong case for a Bool key. The typed read falls back to the
            // default and emits a `.typeMismatch` event — visible in the Events section.
            // This is what a stale remote value or a mistyped override looks like.
            DemoFeature.typeMismatchDemo.lookupKey: .string("on"),

            DemoConfig.apiBaseURL.lookupKey: .string("https://api.local.example"),
            DemoConfig.welcomeMessage.lookupKey: .string(
                "Local defaults are active until the remote config refreshes."
            )
        ]
    }
}
