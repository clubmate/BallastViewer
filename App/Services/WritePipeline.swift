import BallastCore
import Foundation
import GRDB

/// Serialises ALL write-through mutations of one library.
///
/// The mutation contract persists asynchronously — but spawning an unstructured
/// `Task` per mutation gives NO ordering guarantee between tasks: two quick
/// ratings on the same photo could commit in reverse order, leaving the DB
/// permanently behind the in-memory truth. One long-lived worker draining an
/// AsyncStream commits strictly in submission order.
///
/// Ordering only holds if *every* write goes through here: a write issued
/// directly against the pool could commit before jobs queued earlier (e.g. a
/// keyword deletion overtaking a queued assignment insert). Hence the three
/// entry points: `submit` (fire-and-forget), `submitAndWait` (awaitable, for
/// writes whose result the caller needs), and `flushSync` (barrier for the
/// rare legacy synchronous writes in `LibraryController.writeSync`).
///
/// Lifetime is bound to one open library: `shutdown()` finishes the stream and
/// drains pending writes before the caller closes the pool.
final class WritePipeline: Sendable {
    typealias Job = @Sendable (Database) throws -> Void

    /// Thrown by `submitAndWait` jobs after handing the error to the awaiting
    /// caller: the rethrow rolls the transaction back, the marker tells the
    /// worker not to report it a second time through `onError`.
    private struct HandledJobError: Error {}

    private let continuation: AsyncStream<Job>.Continuation
    private let worker: Task<Void, Never>

    init(pool: DatabasePool, onError: @escaping @Sendable @MainActor (String) -> Void) {
        let (stream, continuation) = AsyncStream<Job>.makeStream()
        self.continuation = continuation
        worker = Task {
            for await job in stream {
                do {
                    try await pool.write(job)
                } catch is HandledJobError {
                    // Already delivered to the awaiting caller.
                } catch {
                    let message = error.localizedDescription
                    // Fire-and-forget: the worker must never *await* the
                    // MainActor — `flushSync` blocks the main thread on this
                    // very worker, and an awaited hop would deadlock.
                    Task { @MainActor in onError(message) }
                }
            }
        }
    }

    /// Enqueues a write; jobs commit in submission order.
    func submit(_ job: @escaping Job) {
        continuation.yield(job)
    }

    /// Enqueues a write in the same ordered lane and waits for its result.
    /// For writes whose outcome the caller needs (generated ids, fetched
    /// mirrors) without breaking the global commit order.
    func submitAndWait<T: Sendable>(
        _ body: @escaping @Sendable (Database) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { resume in
            let result = continuation.yield { db in
                do {
                    resume.resume(returning: try body(db))
                } catch {
                    resume.resume(throwing: error)
                    throw HandledJobError()
                }
            }
            if case .enqueued = result {} else {
                // Stream already finished (library closing) — never leave the
                // caller suspended.
                resume.resume(throwing: CancellationError())
            }
        }
    }

    /// Suspends until everything currently queued has committed.
    func flush() async {
        try? await submitAndWait { _ in }
    }

    /// Blocks until everything currently queued has committed. Only for the
    /// rare synchronous structural edits (`LibraryController.writeSync`) that
    /// must not overtake queued write-through jobs. The queue holds nothing
    /// but single-row UPDATEs, so the wait is bounded and normally zero.
    func flushSync() {
        let semaphore = DispatchSemaphore(value: 0)
        let result = continuation.yield { _ in semaphore.signal() }
        guard case .enqueued = result else { return }
        semaphore.wait()
    }

    /// Stops accepting jobs and waits until everything pending has committed.
    func shutdown() async {
        continuation.finish()
        await worker.value
    }
}
