import SwiftUI
import TGFeatureFlag

struct ContentView: View {
    @Environment(FeatureFlagService.self) private var service
    @State private var showingCheckoutAlert = false
    @State private var isRefreshing = false
    @State private var lastRefreshSummary = "Not refreshed yet"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DemoHeroCard()
                }

                Section("Flag Resolution") {
                    ResolutionRow(
                        title: "New Home Design",
                        detail: "Rendered with FeatureGate",
                        isEnabled: service.isEnabled(DemoFeature.newHomeDesign)
                    )
                    ResolutionRow(
                        title: "Experimental Checkout",
                        detail: "Used in button flow branching",
                        isEnabled: service.isEnabled(DemoFeature.experimentalCheckout)
                    )
                    ResolutionRow(
                        title: "Social Tab",
                        detail: "Provider priority demo",
                        isEnabled: service.isEnabled(DemoFeature.socialTab)
                    )
                }

                Section("Configuration") {
                    LabeledContent("API Base URL") {
                        Text(service.stringValue(for: DemoFeature.apiBaseURL))
                            .font(.caption)
                            .monospaced()
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Welcome Message") {
                        Text(service.stringValue(for: DemoFeature.welcomeMessage))
                            .font(.caption)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Rollout Flags") {
                    ForEach(CheckoutFeature.allCases, id: \.self) { feature in
                        ResolutionRow(
                            title: feature.description,
                            detail: feature.qualifiedKey,
                            isEnabled: service.isEnabled(feature)
                        )
                    }
                }

                Section("Actions") {
                    Button("Try Checkout Flow") {
                        showingCheckoutAlert = true
                    }

                    Button {
                        refreshRemoteConfig()
                    } label: {
                        HStack {
                            Text("Refresh Remote Provider")
                            Spacer()
                            if isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(isRefreshing)

                    LabeledContent("Last Refresh") {
                        Text(lastRefreshSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Debug Tools") {
                    NavigationLink("Edit DemoFeature Overrides") {
                        FeatureFlagDebugView<DemoFeature>()
                    }

                    NavigationLink("Edit CheckoutFeature Overrides") {
                        FeatureFlagDebugView<CheckoutFeature>()
                    }
                }
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

    private func refreshRemoteConfig() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task { @MainActor in
            let failures = await service.refresh()
            lastRefreshSummary = failures == 0
                ? "Remote config refreshed successfully"
                : "Refresh completed with \(failures) failure(s)"
            isRefreshing = false
        }
    }
}

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
