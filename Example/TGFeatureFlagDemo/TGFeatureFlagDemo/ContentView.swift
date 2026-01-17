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
                        if let remoteProvider = service.provider(ofType: MockRemoteProvider.self) {
                            remoteProvider.fetchRemoteConfig {
                                service.triggerUpdate()
                                isFetching = false
                            }
                        } else {
                            isFetching = false
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
                    
                    Text("Fetching will:\n• Disable 'New Home UI'\n• Enable 'Social Tab'\n• Change API URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
    
    @State private var isFetching = false
}
