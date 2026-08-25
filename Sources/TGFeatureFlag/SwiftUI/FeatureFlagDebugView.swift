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

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                VStack(alignment: .leading) {
                    Text(feature.description)
                        .font(.headline)
                    Text(feature.lookupKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if debugProvider?.value(for: feature.lookupKey) != nil {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.orange)
                }
            }

            switch feature.defaultValue {
            case .bool(let boolDefault):
                BoolEditor(feature: feature, defaultValue: boolDefault, debugProvider: debugProvider)
            case .string(let stringDefault):
                StringEditor(feature: feature, defaultValue: stringDefault, debugProvider: debugProvider)
            case .int(let intDefault):
                IntEditor(feature: feature, defaultValue: intDefault, debugProvider: debugProvider)
            case .double(let doubleDefault):
                DoubleEditor(feature: feature, defaultValue: doubleDefault, debugProvider: debugProvider)
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
        service.boolValue(for: feature)
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { localValue },
            set: { newValue in
                localValue = newValue
                debugProvider?.setOverride(for: feature, value: .bool(newValue))
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
        service.intValue(for: feature)
    }

    var body: some View {
        HStack {
            Stepper(value: Binding(
                get: { localValue },
                set: { newValue in
                    localValue = newValue
                    debugProvider?.setOverride(for: feature, value: .int(newValue))
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

            if debugProvider?.value(for: feature.lookupKey) != nil {
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
        service.doubleValue(for: feature)
    }

    var body: some View {
        HStack {
            TextField("Value", value: Binding(
                get: { localValue },
                set: { newValue in
                    localValue = newValue
                    debugProvider?.setOverride(for: feature, value: .double(newValue))
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

            if debugProvider?.value(for: feature.lookupKey) != nil {
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
        service.stringValue(for: feature)
    }

    var body: some View {
        HStack {
            TextField("Value", text: Binding(
                get: { localValue },
                set: { newValue in
                    localValue = newValue
                    debugProvider?.setOverride(for: feature, value: .string(newValue))
                    service.triggerUpdate()
                }
            ))
            .textFieldStyle(.roundedBorder)

            if debugProvider?.value(for: feature.lookupKey) != nil {
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
