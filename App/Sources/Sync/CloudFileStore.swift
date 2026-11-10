import Foundation
import CloudKit
import CryptoKit
import ComicCore

/// Book assets are deliberately outside the CKSyncEngine metadata zone.
/// Fetching the library must never fetch these records or their archive assets.
enum CloudFileStore {
    static let zoneID = CKRecordZone.ID(zoneName: CloudSyncEnvironment.zoneName("BookFiles"), ownerName: CKCurrentUserDefaultName)
    static func recordID(_ contentID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "file-" + contentID, zoneID: zoneID)
    }

    static func hashFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            try Task.checkCancellation()
            let count = try autoreleasepool { () throws -> Int in
                let data = try handle.read(upToCount: 1 << 20) ?? Data()
                if !data.isEmpty { hash.update(data: data) }
                return data.count
            }
            if count == 0 { break }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func info(_ contentID: String, in database: CKDatabase) async throws -> CKRecord? {
        do {
            let results = try await database.records(for: [recordID(contentID)], desiredKeys: ["contentID", "size"])
            return try results[recordID(contentID)]?.get()
        } catch let error as CKError where error.code == .unknownItem { return nil }
    }

    static func matches(_ record: CKRecord, contentID: String, size: Int64) -> Bool {
        record["contentID"] as? String == contentID && (record["size"] as? NSNumber)?.int64Value == size
    }

    static func fileRecord(contentID: String, size: Int64, file: URL) -> CKRecord {
        let record = CKRecord(recordType: "BookFile", recordID: recordID(contentID))
        record["contentID"] = contentID as CKRecordValue
        record["size"] = NSNumber(value: size)
        record["archive"] = CKAsset(fileURL: file)
        return record
    }
}
