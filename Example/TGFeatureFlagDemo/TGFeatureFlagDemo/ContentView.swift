import SwiftUI
import TGFeatureFlag

struct ContentView: View {
    @Environment(FeatureFlagService.self) var flags
    
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
            
            // Scenario 1: Tab Control (Social Tab Visibility)
            if flags.isEnabled(DemoFeature.socialTab) {
                SocialView()
                    .tabItem {
                        Label("Social", systemImage: "person.2")
                    }
            }
            
            // Scenario 5: View with Conditional Navigation
            ProductDetailContainerView()
                .tabItem {
                    Label("Product", systemImage: "cart")
                }
            
            // New: Advanced features demo (Rollout, Groups, Logger)
            AdvancedView()
                .tabItem {
                    Label("Advanced", systemImage: "wand.and.stars")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

struct HomeView: View {
    @Environment(FeatureFlagService.self) var service
    @State private var showCheckoutAlert = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Scenario 2: View Toggling (New vs Old Design)
                    FeatureGate(DemoFeature.newHomeDesign) {
                        VStack {
                            Image(systemName: "star.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.yellow)
                            Text("Modern Home Design")
                                .font(.title)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    } fallback: {
                        Text("Legacy Home Design")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.gray.opacity(0.2))
                    }
                    
                    // Scenario 3: Logic Branching (Checkout Flow)
                    Button("Checkout Action") {
                        showCheckoutAlert = true
                    }
                    .buttonStyle(.borderedProminent)
                    .alert("Checkout Flow", isPresented: $showCheckoutAlert) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        if service.isEnabled(DemoFeature.experimentalCheckout) {
                            Text("Navigating to Checkout V2 (New Flow)")
                        } else {
                            Text("Navigating to Legacy Checkout (Old Flow)")
                        }
                    }
                    
                    // Scenario 4: Configuration Value (API URL)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Configuration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Text("API:")
                                .fontWeight(.bold)
                            Text(service.value(for: DemoFeature.apiBaseUrl) as String)
                                .font(.monospaced(.body)())
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        FeatureFlagDebugView<DemoFeature>()
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        }
    }
}

// Scenario 5: Navigation vs No-Navigation & Conditional Routing
struct ProductDetailContainerView: View {
    @Environment(FeatureFlagService.self) var service
    
    var body: some View {
        // Always use NavigationStack to support internal links,
        // but control the visibility of the system navigation bar.
        NavigationStack {
            ProductDetailContent()
                .navigationTitle("Product Details")
                #if os(iOS)
                .toolbar(service.isEnabled(DemoFeature.detailedNavigation) ? .visible : .hidden, for: .navigationBar)
                #endif
                .background(Color(uiColor: .systemBackground))
        }
    }
}

struct ProductDetailContent: View {
    @Environment(FeatureFlagService.self) var service
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "cube.box.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 150)
                    .foregroundStyle(.orange)
                    .padding(.top)
                
                Text("Amazing Product")
                    .font(.title)
                    .bold()
                
                Text("Price: $99.99")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                
                // Conditional Navigation Link
                NavigationLink {
                    if service.isEnabled(DemoFeature.detailedNavigation) {
                        DetailedSpecView()
                    } else {
                        SimpleSpecView()
                    }
                } label: {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("View Specifications")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Description")
                        .font(.headline)
                    
                    Text("This is a high-quality product that demonstrates the flexibility of our feature flag system.\n\nTry clicking 'View Specifications' above. It routes to different screens based on the feature flag.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                if !service.isEnabled(DemoFeature.detailedNavigation) {
                    Text("Tip: Enable 'Detailed View Navigation' in Debug Menu to see native navigation bar and detailed specs.")
                        .font(.caption)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.top)
                }
            }
            .padding()
        }
    }
}

struct DetailedSpecView: View {
    var body: some View {
        List {
            Section("Technical Specs") {
                LabeledContent("Material", value: "Titanium Alloy")
                LabeledContent("Weight", value: "150g")
                LabeledContent("Dimensions", value: "140 x 70 x 7 mm")
                LabeledContent("Water Resistance", value: "IP68")
            }
            
            Section("Features") {
                Text("Wireless Charging")
                Text("Face ID")
                Text("5G Connectivity")
            }
        }
        .navigationTitle("Full Specifications")
    }
}

struct SimpleSpecView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 50))
                .foregroundStyle(.gray)
            
            Text("Basic Specifications")
                .font(.title2)
                .bold()
            
            Text("Material: Titanium\nWeight: 150g")
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding()
        // No navigation title in simple mode to match the "No Nav" theme,
        // or we could add one if the parent stack allows it.
        // Since parent hides navbar, this will be full screen content effectively.
    }
}

// MARK: - Advanced Features Demo

struct AdvancedView: View {
    @Environment(FeatureFlagService.self) var service
    @Environment(DemoLogger.self) var logger
    
    var body: some View {
        NavigationStack {
            List {
                // --- RolloutProvider Demo ---
                Section {
                    RolloutRow(
                        title: "Checkout V2 Flow",
                        feature: CheckoutFeature.v2Flow,
                        percentage: 75
                    )
                    RolloutRow(
                        title: "New Payment UI",
                        feature: CheckoutFeature.newPayment,
                        percentage: 50
                    )
                    RolloutRow(
                        title: "Express Shipping",
                        feature: CheckoutFeature.expressShipping,
                        percentage: 100
                    )
                } header: {
                    Label("RolloutProvider", systemImage: "chart.pie.fill")
                } footer: {
                    Text("Deterministic hash-based rollout for user \"demo-user-001\". Results vary per user ID.")
                        .font(.caption)
                }
                
                // --- FeatureFlagGroup Demo ---
                Section {
                    ForEach(Array(CheckoutFeature.allCases), id: \.rawValue) { feature in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.description)
                                    .font(.body)
                                Text("Key: \"\(feature.qualifiedKey)\"")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospaced()
                            }
                            Spacer()
                            Image(systemName: service.isEnabled(feature) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(service.isEnabled(feature) ? .green : .gray)
                        }
                    }
                } header: {
                    Label("FeatureFlagGroup", systemImage: "folder.fill")
                } footer: {
                    Text("Grouped flags use qualified keys with \"checkout.\" prefix for provider lookups.")
                        .font(.caption)
                }
                
                // --- FeatureFlagLogger Demo ---
                Section {
                    if logger.entries.isEmpty {
                        Text("No resolution events yet. Navigate around to generate logs.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(logger.entries.prefix(10)) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(entry.flag)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .monospaced()
                                    Spacer()
                                    Text(entry.value)
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                        .monospaced()
                                }
                                Text("via \(entry.provider)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Label("FeatureFlagLogger", systemImage: "text.magnifyingglass")
                } footer: {
                    Text("Shows the last 10 flag resolution events recorded by the DemoLogger.")
                        .font(.caption)
                }
                
                // --- Priority Chain Visualization ---
                Section {
                    PriorityRow(name: "Debug", priority: "highest", color: .red)
                    PriorityRow(name: "Rollout", priority: "custom(80)", color: .orange)
                    PriorityRow(name: "Remote Config", priority: "custom(60)", color: .yellow)
                    PriorityRow(name: "UserDefaults", priority: "custom(40)", color: .blue)
                    PriorityRow(name: "Local Default", priority: "lowest", color: .gray)
                } header: {
                    Label("Priority Chain", systemImage: "arrow.up.arrow.down.circle.fill")
                }
            }
            .navigationTitle("Advanced")
        }
    }
}

struct RolloutRow: View {
    @Environment(FeatureFlagService.self) var service
    let title: String
    let feature: CheckoutFeature
    let percentage: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text("\(percentage)% rollout")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(service.isEnabled(feature) ? "IN" : "OUT")
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(service.isEnabled(feature) ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                .cornerRadius(6)
        }
    }
}

struct PriorityRow: View {
    let name: String
    let priority: String
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(name)
                .font(.body)
            Spacer()
            Text(priority)
                .font(.caption)
                .monospaced()
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Social View

struct SocialView: View {
    var body: some View {
        NavigationStack {
            List(0..<5) { i in
                Text("Post #\(i + 1)")
            }
            .navigationTitle("Social Feed")
        }
    }
}

struct SettingsView: View {
    @Environment(FeatureFlagService.self) var service
    
    @State private var isFetching = false
    @State private var refreshError: String?
    
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Feature Flags (Debug)") {
                    FeatureFlagDebugView<DemoFeature>()
                }
                
                Section("App Info") {
                    Text("Version 1.0.0")
                }
                
                Section("Remote Config Simulation") {
                    Button {
                        isFetching = true
                        Task {
                            let failures = await service.refresh()
                            isFetching = false
                            if failures > 0 {
                                refreshError = "\(failures) provider(s) failed to refresh"
                            } else {
                                refreshError = nil
                            }
                        }
                    } label: {
                        HStack {
                            Text("Fetch Remote Config")
                            if isFetching {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isFetching)
                    
                    if let refreshError {
                        Text(refreshError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    Text("Fetching will:\n• Disable 'New Home UI'\n• Enable 'Social Tab'\n• Change API URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
