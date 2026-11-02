import Foundation

/// Polls a condition until it holds or the timeout elapses.
///
/// Needed wherever a change travels through an actor hop, since there is no synchronous
/// point at which the effect is guaranteed to have landed.
func waitUntil(
    timeout: Duration = .milliseconds(500),
    _ condition: @Sendable () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}
