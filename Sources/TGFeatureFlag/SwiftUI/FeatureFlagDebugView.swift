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
    @State private var localValue: Bool
    
    init(feature: F, defaultValue: Bool, debugProvider: DebugProvider?) {
        self.feature = feature
        self.defaultValue = defaultValue
        self.debugProvider = debugProvider
        _localValue = State(initialValue: defaultValue)
    }
    
    private var resolvedValue: Bool {
        service.value(for: feature)
    }
    
    var body: some View {
        Toggle(isOn: Binding(
            get: { localValue },
            set: { newValue in
                localValue = newValue
                debugProvider?.setOverride(for: feature, value: newValue)
                service.triggerUpdate()
            }
        )) {
            Text(localValue ? "ON" : "OFF")
                .bold()
                .foregroundStyle(localValue ? .green : .red)
        }
        .onAppear {
            localValue = resolvedValue
        }
        .onChange(of: resolvedValue) { _, newValue in
            if localValue != newValue {
                localValue = newValue
            }
        }
    }
}

private struct IntEditor<F: FeatureFlagKey>: View {
    let feature: F
    let defaultValue: Int
    let debugProvider: DebugProvider?
    @Environment(FeatureFlagService.self) private var service
    @State private var localValue: Int
    
    init(feature: F, defaultValue: Int, debugProvider: DebugProvider?) {
        self.feature = feature
        self.defaultValue = defaultValue
        self.debugProvider = debugProvider
        _localValue = State(initialValue: defaultValue)
    }
    
    private var resolvedValue: Int {
        service.value(for: feature)
    }
    
    var body: some View {
        HStack {
            Stepper(value: Binding(
                get: { localValue },
                set: { newValue in
                    localValue = newValue
                    debugProvider?.setOverride(for: feature, value: newValue)
                    service.triggerUpdate()
                }
            )) {
                HStack {
                    Text("Value:")
                        .foregroundStyle(.secondary)
                    Text("\(localValue)")
                        .bold()
                        .monospacedDigit()
                }
            }
            
            if debugProvider?.value(for: feature.rawValue) != nil {
                Button(action: {
                    localValue = defaultValue
                    debugProvider?.setOverride(for: feature, value: nil)
                    service.triggerUpdate()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
        }
        .onAppear {
            localValue = resolvedValue
        }
        .onChange(of: resolvedValue) { _, newValue in
            if localValue != newValue {
                localValue = newValue
            }
        }
    }
}

private struct DoubleEditor<F: FeatureFlagKey>: View {
    let feature: F
    let defaultValue: Double
    let debugProvider: DebugProvider?
    @Environment(FeatureFlagService.self) private var service
    @State private var localValue: Double
    
    init(feature: F, defaultValue: Double, debugProvider: DebugProvider?) {
        self.feature = feature
        self.defaultValue = defaultValue
        self.debugProvider = debugProvider
        _localValue = State(initialValue: defaultValue)
    }
    
    private var resolvedValue: Double {
        service.value(for: feature)
    }
    
    var body: some View {
        HStack {
            TextField("Value", value: Binding(
                get: { localValue },
                set: { newValue in
                    localValue = newValue
                    debugProvider?.setOverride(for: feature, value: newValue)
                    service.triggerUpdate()
                }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            
            Text(String(format: "%.2f", localValue))
                .bold()
                .monospacedDigit()
                .frame(minWidth: 60, alignment: .trailing)
            
            if debugProvider?.value(for: feature.rawValue) != nil {
                Button(action: {
                    localValue = defaultValue
                    debugProvider?.setOverride(for: feature, value: nil)
                    service.triggerUpdate()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
        }
        .onAppear {
            localValue = resolvedValue
        }
        .onChange(of: resolvedValue) { _, newValue in
            if localValue != newValue {
                localValue = newValue
            }
        }
    }
}

private struct StringEditor<F: FeatureFlagKey>: View {
    let feature: F
    let defaultValue: String
    let debugProvider: DebugProvider?
    @Environment(FeatureFlagService.self) private var service
    
    @State private var localValue: String
    
    init(feature: F, defaultValue: String, debugProvider: DebugProvider?) {
        self.feature = feature
        self.defaultValue = defaultValue
        self.debugProvider = debugProvider
        _localValue = State(initialValue: defaultValue)
    }
    
    private var resolvedValue: String {
        service.value(for: feature)
    }
    
    var body: some View {
        HStack {
            TextField("Value", text: Binding(
                get: { localValue },
                set: { newValue in
                    localValue = newValue
                    debugProvider?.setOverride(for: feature, value: newValue)
                    service.triggerUpdate()
                }
            ))
            .textFieldStyle(.roundedBorder)
            
            if debugProvider?.value(for: feature.rawValue) != nil {
                Button(action: {
                    localValue = defaultValue
                    debugProvider?.setOverride(for: feature, value: nil)
                    service.triggerUpdate()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
        }
        .onAppear {
            localValue = resolvedValue
        }
        .onChange(of: resolvedValue) { _, newValue in
            if localValue != newValue {
                localValue = newValue
            }
        }
    }
}
