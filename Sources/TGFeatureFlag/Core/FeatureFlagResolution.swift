import Foundation

/// Shared resolution helpers used by `FeatureFlagResolver` and `FeatureFlagService`.
enum FeatureFlagResolution {
    struct ProviderEntry: Sendable {
        let priority: Int
        let provider: any FeatureFlagProvider
    }

    static func insert(
        _ entry: ProviderEntry,
        into entries: inout [ProviderEntry]
    ) {
        if let index = entries.firstIndex(where: { entry.priority > $0.priority }) {
            entries.insert(entry, at: index)
        } else {
            entries.append(entry)
        }
    }

    static func resolveValue(
        forKey lookupKey: String,
        defaultValue: FeatureFlagValue,
        providers: [ProviderEntry],
        logger: (any FeatureFlagLogger)?
    ) -> FeatureFlagValue {
        for entry in providers {
            if let value = entry.provider.value(for: lookupKey) {
                logger?.log(flag: lookupKey, resolvedBy: entry.provider.name, value: value)
                return value
            }
        }

        logger?.log(flag: lookupKey, resolvedBy: nil, value: defaultValue)
        return defaultValue
    }

    static func resolveValue<F: FeatureFlagKey>(
        for feature: F,
        providers: [ProviderEntry],
        logger: (any FeatureFlagLogger)?
    ) -> FeatureFlagValue {
        resolveValue(
            forKey: feature.lookupKey,
            defaultValue: feature.defaultValue,
            providers: providers,
            logger: logger
        )
    }

    static func isEnabled(
        _ value: FeatureFlagValue,
        defaultValue: FeatureFlagValue
    ) -> Bool {
        value.boolValue ?? defaultValue.boolValue ?? false
    }

    static func snapshot<S: Sequence>(
        for features: S,
        providers: [ProviderEntry],
        logger: (any FeatureFlagLogger)?
    ) -> FeatureFlagSnapshot where S.Element: FeatureFlagKey {
        var values: [String: FeatureFlagValue] = [:]
        for feature in features {
            let key = feature.lookupKey
            values[key] = resolveValue(
                forKey: key,
                defaultValue: feature.defaultValue,
                providers: providers,
                logger: logger
            )
        }
        return FeatureFlagSnapshot(values: values)
    }

    @discardableResult
    static func refresh(
        providers: [ProviderEntry],
        logger: (any FeatureFlagLogger)?
    ) async -> Int {
        var failureCount = 0

        for entry in providers {
            guard let asyncProvider = entry.provider as? any AsyncFeatureFlagProvider else {
                continue
            }
            do {
                try await asyncProvider.fetchValues()
                logger?.log(flag: "*", resolvedBy: asyncProvider.name, value: .string("refreshed"))
            } catch {
                failureCount += 1
                logger?.log(
                    flag: "*",
                    resolvedBy: asyncProvider.name,
                    value: .string("refresh_failed: \(error)")
                )
            }
        }

        return failureCount
    }
}
