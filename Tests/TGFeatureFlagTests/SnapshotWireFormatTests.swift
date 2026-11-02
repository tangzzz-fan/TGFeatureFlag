import Testing
import Foundation
@testable import TGFeatureFlagCore

@Suite("Snapshot wire format")
struct SnapshotWireFormatTests {

    private func encode(_ snapshot: FeatureFlagSnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(snapshot), as: UTF8.self)
    }

    @Test("Encoding is a stable, readable, explicitly typed object")
    func stableShape() throws {
        let snapshot = FeatureFlagSnapshot(values: [
            "a": .bool(true),
            "b": .string("hello"),
            "c": .int(3),
            "d": .double(1.5)
        ])

        let expected = """
        {"values":{"a":{"type":"bool","value":true},\
        "b":{"type":"string","value":"hello"},\
        "c":{"type":"int","value":3},\
        "d":{"type":"double","value":1.5}}}
        """

        #expect(try encode(snapshot) == expected)
    }

    @Test("Integral doubles survive the round trip as doubles")
    func integralDoubleRoundTrip() throws {
        // The reason the wire format carries a type tag: a bare `1` decodes as an integer,
        // so an untagged format would silently turn `.double(1.0)` into `.int(1)`.
        let original = FeatureFlagSnapshot(values: ["x": .double(1.0)])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FeatureFlagSnapshot.self, from: data)

        #expect(decoded == original)
        #expect(decoded["x"] == .double(1.0))
        #expect(decoded["x"] != .int(1))
    }

    @Test("Negative and large values round-trip")
    func edgeValuesRoundTrip() throws {
        let original = FeatureFlagSnapshot(values: [
            "neg": .int(-42),
            "big": .int(Int.max),
            "zero": .double(0.0),
            "empty": .string("")
        ])
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(FeatureFlagSnapshot.self, from: data) == original)
    }

    @Test("Unknown type tag fails with a descriptive error")
    func unknownTypeTag() {
        let json = Data(#"{"type":"json","value":{}}"#.utf8)

        do {
            _ = try JSONDecoder().decode(FeatureFlagValue.self, from: json)
            Issue.record("expected decoding to fail")
        } catch let error as DecodingError {
            guard case .dataCorrupted(let context) = error else {
                Issue.record("expected dataCorrupted, got \(error)")
                return
            }
            #expect(context.debugDescription.contains("json"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("Missing value payload fails instead of defaulting")
    func missingPayload() {
        let json = Data(#"{"type":"bool"}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(FeatureFlagValue.self, from: json)
        }
    }
}
