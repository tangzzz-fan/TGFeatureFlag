import Foundation
import Testing
@testable import TGFeatureFlagCore

/// The bare-literal decoding path.
///
/// Backends write `{"value": true}` rather than the tagged form this library emits, so the
/// decoder has to guess the case from JSON syntax. These tests pin the guesses — including
/// two places where the guess cannot match what a hand-written payload meant.
@Suite("Bare literal decoding")
struct ValueDecodingTests {

    private func decode(_ json: String) throws -> FeatureFlagValue {
        try JSONDecoder().decode(FeatureFlagValue.self, from: Data(json.utf8))
    }

    @Test("Booleans decode as booleans, not as the strings \"true\"/\"false\"")
    func booleans() throws {
        #expect(try decode("true") == .bool(true))
        #expect(try decode("false") == .bool(false))
    }

    @Test("A number without a fraction decodes as an integer")
    func integers() throws {
        #expect(try decode("0") == .int(0))
        #expect(try decode("1") == .int(1))
        #expect(try decode("-42") == .int(-42))
    }

    @Test("A number with a fraction decodes as a double")
    func doubles() throws {
        #expect(try decode("1.5") == .double(1.5))
        #expect(try decode("-0.25") == .double(-0.25))
    }

    @Test("A quoted literal stays a string even when it looks like a bool or a number")
    func quotedLiteralsStayStrings() throws {
        // A backend that means "the word true" must be able to say so.
        #expect(try decode(#""true""#) == .string("true"))
        #expect(try decode(#""1""#) == .string("1"))
        #expect(try decode(#""""#) == .string(""))
    }

    @Test("Integers beyond Int.max fall back to a double instead of failing")
    func beyondIntRange() throws {
        // Not lossless — 2^53 already loses integer precision in a double — but the payload
        // still decodes rather than taking the whole document down.
        #expect(try decode("9223372036854775808") == .double(9.223372036854776e+18))
        #expect(try decode("9007199254740993") == .int(9007199254740993))
    }

    @Test("Numbers too large for a double fail the payload")
    func beyondDoubleRange() {
        #expect(throws: DecodingError.self) {
            _ = try decode("1e400")
        }
    }

    @Test("null and objects without a type tag fail with a message that says what to send")
    func unsupportedShapes() {
        for json in ["null", #"{"nested":1}"#, "[1,2]"] {
            do {
                _ = try decode(json)
                Issue.record("expected \(json) to fail")
            } catch let error as DecodingError {
                guard case .dataCorrupted(let context) = error else {
                    Issue.record("expected dataCorrupted for \(json), got \(error)")
                    return
                }
                #expect(context.debugDescription.contains("tagged flag value"))
            } catch {
                Issue.record("unexpected error for \(json): \(error)")
            }
        }
    }

    @Test("A tagged value whose payload has the wrong type fails")
    func taggedPayloadMismatch() {
        #expect(throws: DecodingError.self) {
            _ = try decode(#"{"type":"int","value":"3"}"#)
        }
    }

    // MARK: - Documented limitations

    /// `JSONDecoder` erases the difference between `1`, `1.0` and `1e3`: all three arrive as
    /// an integer-valued number, so the decoder's Int-first order turns them all into `.int`.
    ///
    /// Consequence: a payload that writes `{"value": 1.0}` for a `Double` flag resolves as
    /// `.int(1)`, which then fails the typed read and falls back to the key's default (with a
    /// `typeMismatch` event). Emit the tagged form, or a non-integral value such as `1.5`, when
    /// the flag is a double.
    @Test("An integral literal written with a decimal point decodes as an integer")
    func integralLiteralLosesItsDecimalPoint() throws {
        #expect(try decode("1.0") == .int(1))
        #expect(try decode("-0.0") == .int(0))
        #expect(try decode("1e3") == .int(1000))
    }

    @Test("A rollout payload inherits the limitation, and the typed read falls back")
    func rolloutPayloadHitsTheSameLimit() throws {
        enum Multiplier: String, TypedFeatureFlag {
            case factor = "config_factor"
            var typedDefaultValue: Double { 0.5 }
        }

        let payload = Data(#"{"rollouts":{"config_factor":{"percentage":100,"value":1.0}}}"#.utf8)
        let configuration = try JSONDecoder().decode(RolloutConfiguration.self, from: payload)

        #expect(configuration.ignoredKeys.isEmpty)
        #expect(configuration["config_factor"]?.value == .int(1))

        // The rollout is live, but the value cannot be read as the declared type, so the app
        // runs on its default. This is the failure the limitation produces.
        let snapshot = FeatureFlagSnapshot(values: [Multiplier.factor.lookupKey: .int(1)])
        #expect(snapshot.value(for: Multiplier.factor) == 0.5)
    }
}
