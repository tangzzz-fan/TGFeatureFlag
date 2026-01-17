import SwiftUI

/// A debug view to view and toggle feature flags at runtime.
public struct FeatureFlagDebugView<F: FeatureFlagKey & CaseIterable>: View {
    @Environment(FeatureFlagService.self) private var service
    
    private var debugProvider: DebugProvider? {
        service.provider(ofType: DebugProvider.self)
    }
    
    public init() {}
    
    public var body: some View {
        List {
            Section("Feature Flags") {
                ForEach(Array(F.allCases), id: \.self) { feature in
                    FlagRow(feature: feature, debugProvider: debugProvider)
                }
            }
            
            if let provider = debugProvider {
                Section {
                    Button("Reset All Overrides") {
                        provider.reset()
                        service.triggerUpdate()
                    }
                    .foregroundStyle(.red)
                }
            } else {
                Text("No DebugProvider registered.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Feature Flags")
    }
}

private struct FlagRow<F: FeatureFlagKey>: View {
    let feature: F
    let debugProvider: DebugProvider?
    @Environment(FeatureFlagService.self) private var service
    
    // We determine the type based on defaultValue
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                VStack(alignment: .leading) {
                    Text(feature.description)
                        .font(.headline)
                    Text(feature.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                // Value Display & Override Indicator
                if debugProvider?.value(for: feature.rawValue) != nil {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
            
            // Editor based on type
            if let boolDefault = feature.defaultValue as? Bool {
                BoolEditor(feature: feature, defaultValue: boolDefault, debugProvider: debugProvider)
            } else if let stringDefault = feature.defaultValue as? String {
                StringEditor(feature: feature, defaultValue: stringDefault, debugProvider: debugProvider)
            } else {
                Text("Unsupported Type: \(type(of: feature.defaultValue))")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct BoolEditor<F: FeatureFlagKey>: View {
    let feature: F
    let defaultValue: Bool
    let debugProvider: DebugProvider?
    @Environment(FeatureFlagService.self) private var service
    
    var body: some View {
        let currentValue = service.value(for: feature) as Bool
        
        Toggle(isOn: Binding(
            get: { currentValue },
            set: { newValue in
                debugProvider?.setOverride(for: feature, value: newValue)
                service.triggerUpdate()
            }
        )) {
            Text(currentValue ? "ON" : "OFF")
                .bold()
                .foregroundStyle(currentValue ? .green : .red)
        }
    }
}

private struct StringEditor<F: FeatureFlagKey>: View {
    let feature: F
    let defaultValue: String
    let debugProvider: DebugProvider?
    @Environment(FeatureFlagService.self) private var service
    
    @State private var text: String = ""
    
    var body: some View {
        let currentValue = service.value(for: feature) as String
        
        HStack {
            TextField("Value", text: Binding(
                get: { currentValue },
                set: { newValue in
                    debugProvider?.setOverride(for: feature, value: newValue)
                    service.triggerUpdate()
                }
            ))
            .textFieldStyle(.roundedBorder)
            
            if debugProvider?.value(for: feature.rawValue) != nil {
                Button(action: {
                    debugProvider?.setOverride(for: feature, value: nil)
                    service.triggerUpdate()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
        }
    }
}
