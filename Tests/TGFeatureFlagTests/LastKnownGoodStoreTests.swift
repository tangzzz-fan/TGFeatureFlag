import Testing
import Foundation
@testable import TGFeatureFlagCore

@Suite("Last known good cache")
struct LastKnownGoodStoreTests {

    private func makeStore() -> LastKnownGoodStore {
        LastKnownGoodStore(
            namespace: "tests",
            directory: FileManager.default.temporaryDirectory
                .appending(path: "tgff-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        )
    }

    @Test("A saved snapshot is read back by a new store instance")
    func roundTrip() throws {
        let store = makeStore()
        let snapshot = FeatureFlagSnapshot(values: [
            BoolTestFeature.booleanFeature.lookupKey: .bool(true),
            StringTestFeature.stringFeature.lookupKey: .string("cached"),
            IntTestFeature.intFeature.lookupKey: .int(11)
        ])

        try store.save(snapshot)

        // A fresh instance, as on the next launch.
        let reopened = LastKnownGoodStore(namespace: "tests", directory: store.fileURL.deletingLastPathComponent())
        #expect(reopened.load() == snapshot)
    }

    @Test("Loading a missing file yields nil rather than throwing")
    func missingFile() {
        #expect(makeStore().load() == nil)
    }

    @Test("A corrupt file yields nil so launch can fall back to defaults")
    func corruptFile() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{ this is not json".utf8).write(to: store.fileURL)

        #expect(store.load() == nil)
    }

    @Test("A file with an unknown value type yields nil")
    func unknownTypeTag() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let json = #"{"values":{"x":{"type":"json","value":{}}}}"#
        try Data(json.utf8).write(to: store.fileURL)

        #expect(store.load() == nil)
    }

    @Test("Clearing removes the cache and is safe to repeat")
    func clear() throws {
        let store = makeStore()
        try store.save(FeatureFlagSnapshot(values: ["a": .bool(true)]))

        try store.clear()
        #expect(store.load() == nil)

        try store.clear()
        #expect(store.load() == nil)
    }

    @Test("Namespaces do not overwrite each other")
    func namespaceIsolation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "tgff-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let first = LastKnownGoodStore(namespace: "first", directory: directory)
        let second = LastKnownGoodStore(namespace: "second", directory: directory)

        try first.save(FeatureFlagSnapshot(values: ["a": .bool(true)]))
        try second.save(FeatureFlagSnapshot(values: ["a": .bool(false)]))

        #expect(first.load()?["a"] == .bool(true))
        #expect(second.load()?["a"] == .bool(false))
    }

    @Test("Cold start resolves from cache instead of defaults, before any refresh")
    func coldStartUsesCache() throws {
        let store = makeStore()
        try store.save(FeatureFlagSnapshot(values: [BoolTestFeature.booleanFeature.lookupKey: .bool(true)]))

        // A launch with no network: only defaults plus whatever is on disk.
        let cold = FeatureFlagResolver()
        cold.register(provider: LocalProvider(flags: [:]), priority: .lowest)
        #expect(cold.isEnabled(BoolTestFeature.booleanFeature) == false, "defaults alone must be off")

        if let cached = store.load() {
            cold.register(provider: CachedSnapshotProvider(snapshot: cached), priority: .custom(10))
        }

        #expect(cold.isEnabled(BoolTestFeature.booleanFeature) == true, "cached value must win over the default")

        // A refresh landing later must still be able to override the cache.
        cold.register(
            provider: LocalProvider(flags: [BoolTestFeature.booleanFeature.lookupKey: .bool(false)]),
            priority: .custom(50)
        )
        #expect(cold.isEnabled(BoolTestFeature.booleanFeature) == false)
    }
}
