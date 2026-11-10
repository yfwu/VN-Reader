import Foundation

/// Only system copies inside this app's actual Documents/Inbox may be removed
/// after an import. A matching path fragment is never evidence of ownership.
public enum ImportSourceOwnership {
    public static func isAppInboxFile(_ source: URL, documentsDirectory: URL) -> Bool {
        guard source.isFileURL, documentsDirectory.isFileURL,
              source.host == nil || source.host == "" || source.host == "localhost" else { return false }
        let documents = documentsDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true).standardizedFileURL
        // An Inbox symlink must not turn another folder into disposable app storage.
        guard inbox.resolvingSymlinksInPath().path == inbox.path else { return false }
        let resolvedSource = source.standardizedFileURL.resolvingSymlinksInPath()
        let parent = inbox.pathComponents
        let child = resolvedSource.pathComponents
        return child.count > parent.count && child.starts(with: parent)
    }
}
