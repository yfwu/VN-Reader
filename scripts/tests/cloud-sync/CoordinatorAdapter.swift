// Appended only to the temporary coordinator source copy; no network backend exists.
extension CloudSyncCoordinator {
    func auditBind(_ account: String) { state.account = account; enabled = true }
    func auditReceive(_ record: CKRecord) async throws { try await receive(record) }
    func auditRecord(_ hash: String) throws -> CKRecord? { try cloudRecord(for: Self.bookID(hash)) }
    var auditSystemFieldCount: Int { state.systemFields.count }
    func auditResolvedConflict() { resolvedConflictRevision &+= 1 }
    func auditSend(_ send: () async throws -> Void) async throws {
        try await sendResolvingConflicts(ticket: generation, send: send)
    }
}
