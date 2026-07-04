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
            } else if let intDefault = feature.defaultValue as? Int {
                IntEditor(feature: feature, defaultValue: intDefault, debugProvider: debugProvider)
            } else if let doubleDefault = feature.defaultValue as? Double {
                DoubleEditor(feature: feature, defaultValue: doubleDefault, debugProvider: debugProvider)
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

private struct IntEditor<F: FeatureFlagKey>: View {
    let feature: F
    let defaultValue: Int
    let debugProvider: DebugProvider?
    @Environment(FeatureFlagService.self) private var service
    
    var body: some View {
        let currentValue = service.value(for: feature) as Int
        
        HStack {
            Stepper(value: Binding(
                get: { currentValue },
                set: { newValue in
                    debugProvider?.setOverride(for: feature, value: newValue)
                    service.triggerUpdate()
                }
            )) {
                HStack {
                    Text("Value:")
                        .foregroundStyle(.secondary)
                    Text("\(currentValue)")
                        .bold()
                        .monospacedDigit()
                }
            }
            
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

private struct DoubleEditor<F: FeatureFlagKey>: View {
    let feature: F
    let defaultValue: Double
    let debugProvider: DebugProvider?
    @Environment(FeatureFlagService.self) private var service
    
    var body: some View {
        let currentValue = service.value(for: feature) as Double
        
        HStack {
            TextField("Value", value: Binding(
                get: { currentValue },
                set: { newValue in
                    debugProvider?.setOverride(for: feature, value: newValue)
                    service.triggerUpdate()
                }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            
            Text(String(format: "%.2f", currentValue))
                .bold()
                .monospacedDigit()
                .frame(minWidth: 60, alignment: .trailing)
            
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
