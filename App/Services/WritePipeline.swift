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

    /// One queued transaction: the body runs inside `pool.write`; `completion`
    /// (awaitable submissions and barriers) fires only AFTER the transaction
    /// has committed or failed — never from inside it, where a later COMMIT
    /// failure (SQLITE_FULL, IOERR) could still roll the "succeeded" work back.
    private struct QueuedJob: Sendable {
        let body: Job
        let completion: (@Sendable (Result<Void, any Error>) -> Void)?
    }

    private let continuation: AsyncStream<QueuedJob>.Continuation
    private let worker: Task<Void, Never>

    init(pool: DatabasePool, onError: @escaping @Sendable @MainActor (String) -> Void) {
        let (stream, continuation) = AsyncStream<QueuedJob>.makeStream()
        self.continuation = continuation
        worker = Task {
            for await job in stream {
                do {
                    try await pool.write(job.body)
                    job.completion?(.success(()))
                } catch {
                    if let completion = job.completion {
                        // Delivered to the awaiting caller, which reports it.
                        completion(.failure(error))
                    } else {
                        let message = error.localizedDescription
                        // Fire-and-forget: the worker must never *await* the
                        // MainActor — `flushSync` blocks the main thread on
                        // this very worker, and an awaited hop would deadlock.
                        Task { @MainActor in onError(message) }
                    }
                }
            }
        }
    }

    /// Enqueues a write; jobs commit in submission order.
    func submit(_ job: @escaping Job) {
        continuation.yield(QueuedJob(body: job, completion: nil))
    }

    /// Enqueues a write in the same ordered lane and waits for its result.
    /// For writes whose outcome the caller needs (generated ids, fetched
    /// mirrors) without breaking the global commit order. Resumes after the
    /// transaction has committed.
    func submitAndWait<T: Sendable>(
        _ body: @escaping @Sendable (Database) throws -> T
    ) async throws -> T {
        // Written by the body and read by the completion — both run
        // sequentially on the worker, never concurrently.
        let box = ResultBox<T>()
        return try await withCheckedThrowingContinuation { resume in
            let job = QueuedJob(
                body: { db in box.value = try body(db) },
                completion: { outcome in
                    switch outcome {
                    case .success: resume.resume(returning: box.value!)
                    case .failure(let error): resume.resume(throwing: error)
                    }
                }
            )
            if case .enqueued = continuation.yield(job) {} else {
                // Stream already finished (library closing) — never leave the
                // caller suspended.
                resume.resume(throwing: CancellationError())
            }
        }
    }

    private final class ResultBox<T>: @unchecked Sendable {
        var value: T?
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
        let job = QueuedJob(body: { _ in }, completion: { _ in semaphore.signal() })
        guard case .enqueued = continuation.yield(job) else { return }
        semaphore.wait()
    }

    /// Stops accepting jobs and waits until everything pending has committed.
    func shutdown() async {
        continuation.finish()
        await worker.value
    }
}
