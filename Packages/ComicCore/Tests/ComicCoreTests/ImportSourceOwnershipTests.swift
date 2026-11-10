import XCTest
@testable import ComicCore

final class ImportSourceOwnershipTests: XCTestCase {
    func testOnlyActualAppInboxDescendantsAreOwned() throws {
        let root = try Fixtures.tempDir(self)
        let documents = root.appendingPathComponent("App/Documents", isDirectory: true)
        let own = documents.appendingPathComponent("Inbox/book.cbz")
        XCTAssertTrue(ImportSourceOwnership.isAppInboxFile(own, documentsDirectory: documents))
        XCTAssertTrue(ImportSourceOwnership.isAppInboxFile(documents.appendingPathComponent("Inbox/folder/book.cbr"), documentsDirectory: documents))
        for url in [
            documents.appendingPathComponent("Inbox"),
            documents.appendingPathComponent("Inbox-backup/book.cbz"),
            documents.appendingPathComponent("Inbox/../original.cbz"),
            root.appendingPathComponent("Downloads/Documents/Inbox/book.cbz"),
            root.appendingPathComponent("OtherApp/Documents/Inbox/book.cbz"),
            URL(string: "https://example.com/Documents/Inbox/book.cbz")!,
            URL(string: "file://example.com" + own.path)!,
        ] {
            XCTAssertFalse(ImportSourceOwnership.isAppInboxFile(url, documentsDirectory: documents), url.absoluteString)
        }
    }

    func testSourceSymlinkCannotAuthorizeDeletingAnExternalOriginal() throws {
        let root = try Fixtures.tempDir(self)
        let documents = root.appendingPathComponent("App/Documents", isDirectory: true)
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("original.cbz")
        try Data([1, 2, 3]).write(to: original)
        let link = inbox.appendingPathComponent("linked.cbz")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        XCTAssertFalse(ImportSourceOwnership.isAppInboxFile(link, documentsDirectory: documents))
        XCTAssertEqual(try Data(contentsOf: original), Data([1, 2, 3]))
    }

    func testInboxSymlinkCannotAuthorizeAnUnrelatedFolder() throws {
        let root = try Fixtures.tempDir(self)
        let documents = root.appendingPathComponent("App/Documents", isDirectory: true)
        let external = root.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: inbox, withDestinationURL: external)
        let original = external.appendingPathComponent("book.cbz")
        try Data([1]).write(to: original)
        XCTAssertFalse(ImportSourceOwnership.isAppInboxFile(inbox.appendingPathComponent("book.cbz"), documentsDirectory: documents))
        XCTAssertFalse(ImportSourceOwnership.isAppInboxFile(original, documentsDirectory: documents))
    }
}
