import Foundation
import ComicCore

struct CheckFailure: Error { let description: String }
struct SimulatedNetworkError: Error {}
func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
    guard condition() else { throw CheckFailure(description: name) }
    print("PASS: \(name)")
}
@MainActor final class CycleProbe {
    var starts = 0
    var concurrent = 0
    var maximumConcurrent = 0
    private var waiters: [Int: CheckedContinuation<Void, Error>] = [:]
    func run() async throws {
        starts += 1; let id = starts
        concurrent += 1; maximumConcurrent = max(maximumConcurrent, concurrent)
        defer { concurrent -= 1 }
        try await withCheckedThrowingContinuation { waiters[id] = $0 }
    }
    func finish(_ id: Int, failing: Bool = false) throws {
        guard let waiter = waiters.removeValue(forKey: id) else { throw CheckFailure(description: "missing synthetic cycle \(id)") }
        if failing { waiter.resume(throwing: SimulatedNetworkError()) } else { waiter.resume() }
    }
}
@main struct Audit {
    @MainActor static func main() async throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        func setup(_ name: String, enabled: Bool = true) -> (LibraryStore, CloudSyncCoordinator, CycleProbe) {
            let dir = base.appendingPathComponent(name)
            let library = LibraryStore(paths: LibraryPaths(root: dir.appendingPathComponent("support"), cachesRoot: dir.appendingPathComponent("cache"), tempRoot: dir.appendingPathComponent("tmp")))
            let sync = library.cloudSync; let probe = CycleProbe()
            if enabled { sync.auditBind("synthetic-account") }
            sync.auditCycleHandler = { try await probe.run() }
            return (library, sync, probe)
        }
        func settle() async { for _ in 0..<100 { await Task.yield() } }
        func until(_ label: String, _ condition: () -> Bool) async throws {
            for _ in 0..<5000 { if condition() { return }; await Task.yield() }
            throw CheckFailure(description: "scheduler did not reach \(label)")
        }
        func addUnbound(_ library: LibraryStore, localFile: Bool) throws -> BookRecord {
            let book = BookRecord(displayName: "Synthetic", originalFileName: "test.cbz", format: .zip, isSolid: false, fileSize: 3, pageCount: 4, fingerprint: UUID().uuidString, hasCover: false)
            if localFile {
                try FileManager.default.createDirectory(at: library.paths.bookDir(book.id), withIntermediateDirectories: true)
                try Data([1, 2, 3]).write(to: library.paths.archiveFile(book.id, format: book.format))
            }
            try library.add(book)
            return book
        }
        do {
            let (_, sync, probe) = setup("rapid-lifecycle")
            for _ in 0..<30 {
                sync.requestAutomaticSync(.appActive)
                sync.requestAutomaticSync(.bookClosed)
                sync.requestAutomaticSync(.bookOpened)
            }
            try check(probe.starts == 0 && sync.auditHasDebounce, "rapid lifecycle requests debounce without blocking the caller")
            try await until("first automatic cycle") { probe.starts == 1 }
            try check(sync.busy && probe.maximumConcurrent == 1, "one debounced cycle starts for app activation and rapid book switches")
            for _ in 0..<30 { sync.requestAutomaticSync(.readerForeground); sync.synchronize() }
            try check(sync.auditFollowUpPending && probe.starts == 1, "busy automatic and manual requests coalesce into one pending follow-up")
            try probe.finish(1)
            try await until("follow-up cycle") { probe.starts == 2 }
            try check(probe.maximumConcurrent == 1 && !sync.auditFollowUpPending, "follow-up starts only after the previous cycle finishes")
            try probe.finish(2)
            try await until("follow-up completes") { !sync.busy }
            await settle()
            try check(probe.starts == 2 && !sync.auditHasDebounce, "completion alone never creates a third cycle")
        }
        do {
            let (_, sync, probe) = setup("manual-retry")
            sync.requestAutomaticSync(.appOpened)
            sync.synchronize()
            try check(sync.busy && !sync.auditHasDebounce, "manual synchronization starts immediately and cancels the queued debounce")
            try await until("manual cycle") { probe.starts == 1 }
            try probe.finish(1, failing: true)
            try await until("manual failure") { !sync.busy }
            await settle()
            try check(probe.starts == 1 && sync.status != L10n.syncCurrent, "network failure remains visible and does not retry itself")
            sync.synchronize()
            try await until("manual retry") { probe.starts == 2 }
            try probe.finish(2)
            try await until("manual retry complete") { !sync.busy }
            try check(sync.status == L10n.syncCurrent, "a later explicit manual request can retry after a network failure")
        }
        do {
            let (_, sync, probe) = setup("queued-failure")
            sync.synchronize(); try await until("first failing cycle") { probe.starts == 1 }
            sync.requestAutomaticSync(.bookOpened)
            try probe.finish(1, failing: true)
            try await until("one queued retry") { probe.starts == 2 }
            try probe.finish(2, failing: true)
            try await until("second failure") { !sync.busy }
            await settle()
            try check(probe.starts == 2 && !sync.auditFollowUpPending && !sync.auditHasDebounce,
                      "one external request during failure allows one follow-up, never an infinite retry loop")
        }
        do {
            let (_, sync, probe) = setup("disabled-debounce")
            sync.requestAutomaticSync(.appActive)
            sync.setEnabled(false)
            sync.requestAutomaticSync(.bookOpened)
            await settle()
            try check(probe.starts == 0 && !sync.auditHasDebounce && !sync.auditFollowUpPending,
                      "disabling cancels scheduled work and ignores later automatic requests")
        }
        do {
            let (_, sync, probe) = setup("generation-change")
            sync.synchronize(); try await until("old generation starts") { probe.starts == 1 }
            sync.requestAutomaticSync(.bookOpened)
            sync.setEnabled(false)
            sync.setEnabled(true)
            try await until("new generation starts") { probe.starts == 2 }
            try probe.finish(1)
            await settle()
            try check(sync.busy && probe.starts == 2 && !sync.auditFollowUpPending,
                      "old cancelled completion cannot clear a newer generation's busy state or recreate pending work")
            try probe.finish(2); try await until("new generation completes") { !sync.busy }
            await settle()
            try check(probe.starts == 2, "disabled generation's pending follow-up never survives re-enabling")
        }
        do {
            let (_, sync, probe) = setup("halted")
            sync.synchronize(); try await until("cycle before halt") { probe.starts == 1 }
            sync.requestAutomaticSync(.appActive)
            sync.auditHalt()
            sync.requestAutomaticSync(.bookOpened)
            try probe.finish(1)
            await settle()
            try check(!sync.busy && !sync.auditHasDebounce && !sync.auditFollowUpPending && probe.starts == 1,
                      "halting for account/persistence failure cancels pending automatic work")
        }
        do {
            let (library, sync, probe) = setup("missing-archive")
            _ = try addUnbound(library, localFile: false)
            await settle()
            try check(probe.starts == 0, "an unbound catalogue row without an archive does not trigger a retry loop")
            sync.synchronize(); try await until("manual missing-archive cycle") { probe.starts == 1 }
            try probe.finish(1); try await until("missing-archive completion") { !sync.busy }
            for _ in 0..<5 { library.saveNow() }
            await settle()
            try check(probe.starts == 1, "ordinary saves and cycle completion do not repeatedly request missing archive preparation")
        }
        do {
            let (library, sync, probe) = setup("new-import-during-run")
            _ = try addUnbound(library, localFile: true)
            try await until("first import checkpoint") { probe.starts == 1 }
            _ = try addUnbound(library, localFile: true)
            _ = try addUnbound(library, localFile: true)
            try check(sync.auditFollowUpPending && probe.starts == 1, "imports arriving during synchronization retain one follow-up checkpoint")
            try probe.finish(1); try await until("import follow-up") { probe.starts == 2 }
            try probe.finish(2); try await until("import follow-up completes") { !sync.busy }
            library.saveNow(); await settle()
            try check(probe.starts == 2, "unchanged unbound local imports do not self-schedule endlessly after completion")
        }
        print("All actual automatic-sync scheduler checks passed. The transport was injected; no CloudKit backend or real preferences were used.")
    }
}
