import Foundation
import ComicCore

/// Smoke testing is explicit, DEBUG-only, and has its own storage, preferences and
/// CloudKit zones. It never invokes the UI-test hook that deletes a normal library.
enum CloudSyncEnvironment {
    static let smokeRunID: String? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-sync-smoke-test"), index + 1 < args.count else { return nil }
        let value = args[index + 1]
        guard (1...32).contains(value.count), value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }) else { return nil }
        return value
        #else
        return nil
        #endif
    }()
    static let smokeClientID: String = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-sync-smoke-client"), index + 1 < args.count {
            let value = args[index + 1]
            if (1...32).contains(value.count), value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }) { return value }
        }
        #endif
        return "default"
    }()
    static var defaultsPrefix: String { smokeRunID.map { "cloudSync.smoke.\($0).\(smokeClientID)." } ?? "cloudSync." }
    static func zoneName(_ name: String) -> String { smokeRunID.map { "Smoke-\($0)-\(name)" } ?? name }
    static var automaticallyEnable: Bool {
        smokeRunID != nil && ProcessInfo.processInfo.arguments.contains("-sync-smoke-enable")
    }
    static var seedBundledGuide: Bool {
        smokeRunID != nil && ProcessInfo.processInfo.arguments.contains("-sync-smoke-seed-guide")
    }
    static func paths(from original: LibraryPaths) -> LibraryPaths {
        guard let id = smokeRunID else { return original }
        return LibraryPaths(root: original.root.appendingPathComponent("SyncSmoke/\(id)/\(smokeClientID)"),
                            cachesRoot: original.cachesRoot.appendingPathComponent("SyncSmoke/\(id)/\(smokeClientID)"),
                            tempRoot: original.tempRoot.appendingPathComponent("SyncSmoke/\(id)/\(smokeClientID)"))
    }
}
