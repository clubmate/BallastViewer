import BallastCore
import Foundation
import GRDB

/// Serialises the fire-and-forget write-through mutations of one library.
///
/// The mutation contract persists asynchronously — but spawning an unstructured
/// `Task` per mutation gives NO ordering guarantee between tasks: two quick
/// ratings on the same photo could commit in reverse order, leaving the DB
/// permanently behind the in-memory truth. One long-lived worker draining an
/// AsyncStream commits strictly in submission order.
///
/// Lifetime is bound to one open library: `shutdown()` finishes the stream and
/// drains pending writes before the caller closes the pool.
final class WritePipeline: Sendable {
    typealias Job = @Sendable (Database) throws -> Void

    private let continuation: AsyncStream<Job>.Continuation
    private let worker: Task<Void, Never>

    init(pool: DatabasePool, onError: @escaping @Sendable @MainActor (String) -> Void) {
        let (stream, continuation) = AsyncStream<Job>.makeStream()
        self.continuation = continuation
        worker = Task {
            for await job in stream {
                do {
                    try await pool.write(job)
                } catch {
                    let message = error.localizedDescription
                    await onError(message)
                }
            }
        }
    }

    /// Enqueues a write; jobs commit in submission order.
    func submit(_ job: @escaping Job) {
        continuation.yield(job)
    }

    /// Stops accepting jobs and waits until everything pending has committed.
    func shutdown() async {
        continuation.finish()
        await worker.value
    }
}
