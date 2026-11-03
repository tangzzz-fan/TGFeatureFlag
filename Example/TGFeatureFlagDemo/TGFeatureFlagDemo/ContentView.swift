import SwiftUI
import TGFeatureFlag

struct ContentView: View {
    let wiring: DemoWiring

    @Environment(FeatureFlagService.self) private var service

    @State private var isRefreshing = false
    @State private var lastRefreshSummary = "Not refreshed yet"
    @State private var lastReport: FeatureFlagRefreshReport?
    @State private var aggressiveTimeout = false
    @State private var showingCheckoutAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DemoHeroCard()
                }

                resolutionSection
                configurationSection
                rolloutSection
                coldStartSection
                refreshSection
                eventsSection
                snapshotSection
                debugSection
            }
            .navigationTitle("TGFeatureFlag Demo")
            .alert("Checkout Flow", isPresented: $showingCheckoutAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                if service.isEnabled(DemoFeature.experimentalCheckout) {
                    Text("The app would navigate to the new checkout experience.")
                } else {
                    Text("The app would keep using the legacy checkout flow.")
                }
            }
        }
    }

    // MARK: - Resolution

    private var resolutionSection: some View {
        Section("Flag Resolution") {
            ResolutionRow(
                title: "New Home Design",
                detail: "Rendered with FeatureGate",
                isEnabled: service.isEnabled(DemoFeature.newHomeDesign)
            )
            ResolutionRow(
                title: "Experimental Checkout",
                detail: "Branches the button flow",
                isEnabled: service.isEnabled(DemoFeature.experimentalCheckout)
            )
            ResolutionRow(
                title: "Social Tab",
                detail: "Provider priority demo",
                isEnabled: service.isEnabled(DemoFeature.socialTab)
            )
            ResolutionRow(
                title: "Type Mismatch Demo",
                detail: "Bool key, string value in LocalProvider",
                isEnabled: service.isEnabled(DemoFeature.typeMismatchDemo)
            )
        }
    }

    private var configurationSection: some View {
        Section("Configuration") {
            LabeledContent("API Base URL") {
                Text(service.value(for: DemoConfig.apiBaseURL))
                    .font(.caption)
                    .monospaced()
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Welcome Message") {
                Text(service.value(for: DemoConfig.welcomeMessage))
                    .font(.caption)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    // MARK: - Remote rollout

    private var rolloutSection: some View {
        Section {
            ForEach(CheckoutFeature.allCases, id: \.self) { feature in
                ResolutionRow(
                    title: feature.description,
                    detail: "\(feature.qualifiedKey) · \(pushedLabel)",
                    isEnabled: service.isEnabled(feature)
                )
            }

            HStack(spacing: 8) {
                ForEach(DemoWiring.percentagePresets, id: \.self) { percentage in
                    Button("\(percentage)%") {
                        wiring.pushRollouts(all: percentage)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            }

            Button("Clear document (fall through)") {
                wiring.clearRollouts()
            }

            Picker("Identity", selection: userIdBinding) {
                ForEach(DemoWiring.userIds, id: \.self) { userId in
                    Text(userId).tag(userId)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Remote Rollout")
        } footer: {
            Text("Percentages come from a `RolloutConfiguration` document, not from code — moving 5% to 50% needs no release. Buckets are derived from identity + flag key, so switching identity re-assigns every rollout without the document changing.")
        }
    }

    private var pushedLabel: String {
        guard let percentage = wiring.pushedPercentage else { return "no document applied" }
        return "pushed at \(percentage)%"
    }

    private var userIdBinding: Binding<String> {
        Binding(
            get: { wiring.activeUserId },
            set: { wiring.switchUser(to: $0) }
        )
    }

    // MARK: - Cold start

    private var coldStartSection: some View {
        Section {
            LabeledContent("Cache") {
                Text(cacheDescription)
                    .font(.caption)
                    .multilineTextAlignment(.trailing)
            }

            Button("Save current values as last known good") {
                wiring.saveLastKnownGood()
            }

            Button("Clear cache", role: .destructive) {
                wiring.clearLastKnownGood()
            }
        } header: {
            Text("Cold Start")
        } footer: {
            Text("Priming the chain from disk is what stops the interface from flashing defaults and then switching once the first refresh lands. `load()` never throws: a missing or corrupt file falls back to defaults instead of failing the launch.")
        }
    }

    private var cacheDescription: String {
        if let status = wiring.cacheActionStatus {
            return status
        }
        return wiring.primedFromCache
            ? "primed from disk (\(wiring.primedValueCount) values)"
            : "empty — started from defaults"
    }

    // MARK: - Refresh

    private var refreshSection: some View {
        Section {
            Toggle("Aggressive timeout (0.5 s)", isOn: $aggressiveTimeout)

            Button {
                refresh()
            } label: {
                HStack {
                    Text("Refresh Providers")
                    Spacer()
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isRefreshing)

            LabeledContent("Summary") {
                Text(lastRefreshSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            if let lastReport {
                ForEach(lastReport.outcomes, id: \.providerName) { outcome in
                    LabeledContent(outcome.providerName) {
                        Text(outcomeLabel(outcome))
                            .font(.caption)
                            .foregroundStyle(outcome.didRefresh ? Color.secondary : Color.red)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        } header: {
            Text("Refresh")
        } footer: {
            Text("Providers refresh concurrently with a per-provider timeout. The flaky endpoint fails without affecting the others; the aggressive timeout shows the same isolation from a source that hangs instead of throwing.")
        }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let timeout: Duration = aggressiveTimeout ? .milliseconds(500) : .seconds(3)

        Task { @MainActor in
            do {
                let report = try await service.refresh(timeout: timeout)
                lastReport = report
                lastRefreshSummary = summary(for: report)

                // Remember what the app actually resolved, so the next launch starts here.
                if report.hasAnyFreshValue {
                    wiring.saveLastKnownGood()
                }
            } catch is CancellationError {
                lastRefreshSummary = "Cancelled"
            } catch {
                lastRefreshSummary = "Failed: \(error)"
            }
            isRefreshing = false
        }
    }

    private func summary(for report: FeatureFlagRefreshReport) -> String {
        if report.outcomes.isEmpty {
            return "No async providers registered"
        }
        if report.isSuccess {
            return "All \(report.outcomes.count) providers refreshed"
        }
        let failed = report.outcomes.filter { !$0.didRefresh }.map(\.providerName)
        return "\(failed.count) of \(report.outcomes.count) failed: \(failed.joined(separator: ", "))"
    }

    private func outcomeLabel(_ outcome: FeatureFlagRefreshReport.Outcome) -> String {
        switch outcome.result {
        case .refreshed:
            return "refreshed in \(outcome.duration.demoMilliseconds)"
        case .timedOut:
            return "timed out"
        case .failed(let reason):
            return "failed: \(reason)"
        }
    }

    // MARK: - Events

    private var eventsSection: some View {
        Section {
            LabeledContent("Exposures", value: "\(wiring.eventLog.exposureCount)")
            LabeledContent("Refresh events", value: "\(wiring.eventLog.refreshCount)")
            LabeledContent("Type mismatches", value: "\(wiring.eventLog.mismatchCount)")

            if wiring.eventLog.entries.isEmpty {
                Text("No events yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(wiring.eventLog.entries.prefix(6)) { entry in
                    Label(entry.text, systemImage: entry.symbol)
                        .font(.caption)
                        .monospaced()
                }
            }

            Button("Start new exposure session") {
                service.startNewSession()
                wiring.eventLog.reset()
            }
        } header: {
            Text("Events")
        } footer: {
            Text("Exposures are deduplicated per flag and value, so a flag read on every frame still reports once. Starting a new session clears the dedupe. Per-read `.resolved` events are opt-in via `.all` and are not enabled here.")
        }
    }

    // MARK: - Snapshot mode

    private var snapshotSection: some View {
        Section {
            FeatureGate(DemoFeature.socialTab, snapshot: snapshotFlags) {
                Text("Social tab is ON in the snapshot")
                    .foregroundStyle(.green)
            } fallback: {
                Text("Social tab is OFF in the snapshot")
                    .foregroundStyle(.secondary)
            }

            Text("The same `FeatureGate` type, driven by a cold snapshot instead of the environment service. In a Redux app the Store would own this snapshot; here it is rebuilt from the service so both paths are visible side by side.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Snapshot Mode (Redux path)")
        }
    }

    private var snapshotFlags: FeatureFlagSnapshot {
        service.snapshot(for: DemoFeature.allCases)
    }

    // MARK: - Debug tools

    private var debugSection: some View {
        Section("Debug Tools") {
            NavigationLink("Edit DemoFeature Overrides") {
                FeatureFlagDebugView<DemoFeature>()
            }

            NavigationLink("Edit CheckoutFeature Overrides") {
                FeatureFlagDebugView<CheckoutFeature>()
            }

            Button("Try Checkout Flow") {
                showingCheckoutAlert = true
            }
        }
    }
}

// MARK: - Components

private struct DemoHeroCard: View {
    var body: some View {
        FeatureGate(DemoFeature.newHomeDesign) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Modern Home Design Enabled", systemImage: "sparkles.rectangle.stack.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Text("This card is visible because the feature flag resolves to `true`.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } fallback: {
            VStack(alignment: .leading, spacing: 12) {
                Label("Legacy Home Design", systemImage: "rectangle.stack.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Enable the flag in Debug Tools to switch this section to the new design.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
    }
}

private struct ResolutionRow: View {
    let title: String
    let detail: String
    let isEnabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }

            Spacer(minLength: 12)

            Text(isEnabled ? "ON" : "OFF")
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isEnabled ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                .foregroundStyle(isEnabled ? .green : .secondary)
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
    }
}
