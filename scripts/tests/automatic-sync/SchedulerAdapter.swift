// Appended only to the temporary source copy. The real scheduler and Task
// cancellation run unchanged; debounce time is replaced by a cooperative yield.
extension CloudSyncCoordinator {
    private func auditDebounce() async throws { await Task.yield(); try Task.checkCancellation() }
    var auditFollowUpPending: Bool { followUpRequested }
    var auditHasDebounce: Bool { scheduledSync != nil }
    func auditHalt() { stopAfterFailure(SyncFailure.localPersistence) }
}
