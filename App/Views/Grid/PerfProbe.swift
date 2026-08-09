import Darwin
import SwiftUI

/// Debug-only performance gate instrumentation (see docs/PLAN.md steps 5/12).
/// Activated by BV_TEST_PERF=1: measures selection, jump, rating and search
/// latency, then prints pipeline cache stats and memory footprint.
///
/// NOTE: do NOT combine with BV_TEST_QUIT — TestHooks exits before this
/// probe's 2 s warm-up elapses. Launch without it and kill the app instead.
enum PerfProbe {
    @MainActor
    static func runIfRequested(
        photos: [GridPhoto],
        viewModel: CenterViewModel,
        pipeline: ThumbnailPipeline,
        controller: LibraryController
    ) async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard env["BV_TEST_PERF"] != nil, photos.count >= 1000 else { return }
        try? await Task.sleep(for: .seconds(2))
        let clock = ContinuousClock()

        // Selection latency: neighbouring photos, as during culling.
        var selectMs: [Double] = []
        let base = photos.count / 2
        for i in 0..<20 {
            let target = photos[base + i]
            let elapsed = await clock.measure {
                viewModel.selection.selectSingle(target.id)
                await afterRunloopTurn()
            }
            selectMs.append(ms(elapsed))
        }

        // Jumps into random regions: the anchor change makes the grid backend
        // scroll, realizing items far away from the previous viewport.
        var jumpMs: [Double] = []
        for i in 0..<20 {
            let target = photos[(i * 2503 + 137) % photos.count]
            let elapsed = await clock.measure {
                viewModel.selection.selectSingle(target.id)
                await afterRunloopTurn()
            }
            jumpMs.append(ms(elapsed))
        }

        // Step-12 acceptance: keystroke → committed UI turn (< 16 ms) and
        // keystroke → durable in the WAL (< 100 ms). "Durable" is measured by
        // queueing an empty write behind the pending rating UPDATE — the pool
        // serialises writes, so its return implies the mutation reached disk.
        var rateUiMs: [Double] = []
        var rateDurableMs: [Double] = []
        if let library = controller.library {
            for i in 0..<10 {
                let target = photos[base + 40 + i]
                viewModel.selection.selectSingle(target.id)
                await afterRunloopTurn()
                let start = clock.now
                controller.updateRatings(ids: [target.id]) { _ in (i % 5) + 1 }
                await afterRunloopTurn()
                rateUiMs.append(ms(clock.now - start))
                try? await library.pool.write { _ in }
                rateDurableMs.append(ms(clock.now - start))
            }
        }

        // Search latency: the cost of ONE debounced apply (refilter + resort +
        // grid reload) — typing itself only pays this once per pause.
        var searchMs: [Double] = []
        for query in ["photo_1", "photo_12", "zzz-none", ""] {
            let elapsed = await clock.measure {
                viewModel.searchText = query
                viewModel.applySearchNow()
                await afterRunloopTurn()
            }
            searchMs.append(ms(elapsed))
        }

        let stats = pipeline.stats()
        print("BVPERF photos=\(photos.count)")
        print("BVPERF select ms median=\(median(selectMs)) max=\(selectMs.max() ?? 0)")
        print("BVPERF jump ms median=\(median(jumpMs)) max=\(jumpMs.max() ?? 0)")
        print("BVPERF rateUI ms median=\(median(rateUiMs)) max=\(rateUiMs.max() ?? 0)")
        print("BVPERF rateDurable ms median=\(median(rateDurableMs)) max=\(rateDurableMs.max() ?? 0)")
        print("BVPERF search ms median=\(median(searchMs)) max=\(searchMs.max() ?? 0)")
        print("BVPERF thumbs memoryHits=\(stats.memoryHits) diskHits=\(stats.diskHits) decodes=\(stats.decodes)")
        print("BVPERF footprintMB=\(Int(memoryFootprintMB()))")
        if env["BV_TEST_QUIT"] != nil { exit(0) }
        #endif
    }

    #if DEBUG
    /// Resumes after the current main-runloop turn completes — an approximation
    /// of "the UI update for the change above has been committed".
    @MainActor
    private static func afterRunloopTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1e15
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : (sorted[sorted.count / 2] * 10).rounded() / 10
    }

    private static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1_048_576
    }
    #endif
}
