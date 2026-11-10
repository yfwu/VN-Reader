import Foundation
import ComicCore

/// Explains a failure: what happened and what the user can do next.
struct ErrorExplanation: Equatable {
    var title: String
    var message: String
}

enum ErrorMessages {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func explain(_ error: Error) -> ErrorExplanation {
        if let e = error as? LibraryDatabase.PersistenceError {
            let message: String
            switch e {
            case .unavailable: message = L10n.libraryUnavailable
            case .unsupportedVersion: message = L10n.libraryUnsupportedVersion
            }
            return ErrorExplanation(title: L10n.libraryTitle, message: message)
        }
        if let e = error as? ComicError { return explain(e) }
        if error is CancellationError { return explain(ComicError.cancelled) }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError { return explain(ComicError.cancelled) }
        return ErrorExplanation(
            title: String(localized: "error.generic.title", defaultValue: "發生錯誤"),
            message: String(localized: "error.generic.message", defaultValue: "\(ns.localizedDescription)（\(ns.domain) \(ns.code)）"))
    }

    static func explain(_ e: ComicError) -> ErrorExplanation {
        switch e {
        case .sourceUnreadable(let d):
            return .init(title: String(localized: "error.unreadable.title", defaultValue: "無法讀取來源檔案"),
                         message: String(localized: "error.unreadable.message", defaultValue: "來源位置拒絕存取或讀取中斷（\(d)）。請確認檔案已下載到裝置、網路磁碟仍連線，或先在「檔案」App 中把它拷貝到「我的 iPad」再匯入。"))
        case .notAnArchive(let detected):
            if let d = detected {
                return .init(title: String(localized: "error.notarchive.title", defaultValue: "這不是漫畫壓縮檔"),
                             message: String(localized: "error.notarchive.known", defaultValue: "檔案內容是 \(d)，不是 ZIP 或 RAR。VN Reader 目前只支援 CBZ 與 CBR。"))
            }
            return .init(title: String(localized: "error.notarchive.title", defaultValue: "這不是漫畫壓縮檔"),
                         message: String(localized: "error.notarchive.unknown", defaultValue: "檔案開頭不是 ZIP 或 RAR 的格式標記，無法辨識內容（副檔名不會被採信）。請確認檔案是 CBZ 或 CBR。"))
        case .unsupportedArchiveType(let t):
            return .init(title: String(localized: "error.unsupportedtype.title", defaultValue: "不支援的壓縮格式"),
                         message: String(localized: "error.unsupportedtype.message", defaultValue: "這是 \(t) 壓縮檔。目前只支援 ZIP（CBZ）與 RAR（CBR）；請在電腦上轉存成 CBZ 後再匯入。"))
        case .encryptedArchive:
            return .init(title: String(localized: "error.encrypted.title", defaultValue: "檔案有密碼保護"),
                         message: String(localized: "error.encrypted.message", defaultValue: "這個版本不支援加密的壓縮檔。請先在電腦上解除密碼，重新壓縮後再匯入。"))
        case .encryptedEntry(let n):
            return .init(title: String(localized: "error.encryptedentry.title", defaultValue: "此頁有密碼保護"),
                         message: String(localized: "error.encryptedentry.message", defaultValue: "「\(n)」已加密，無法顯示。"))
        case .multiVolumeArchive:
            return .init(title: String(localized: "error.multivolume.title", defaultValue: "不支援分卷壓縮檔"),
                         message: String(localized: "error.multivolume.message", defaultValue: "這是分卷壓縮檔的其中一部分（例如 .part1.rar 或 .z01）。請先在電腦上解壓並重新壓縮成單一檔案。"))
        case .unsupportedCompression(let m):
            return .init(title: String(localized: "error.method.title", defaultValue: "不支援的壓縮方式"),
                         message: String(localized: "error.method.message", defaultValue: "檔案使用「\(m)」壓縮。CBZ 目前只支援標準的「儲存」與「Deflate」方式，請用一般 ZIP 設定重新壓縮。"))
        case .truncatedArchive:
            return .init(title: String(localized: "error.truncated.title", defaultValue: "檔案不完整"),
                         message: String(localized: "error.truncated.message", defaultValue: "壓縮檔在應有的結尾之前就中斷了，通常是下載未完成或複製中斷。請重新下載完整檔案後再匯入。"))
        case .corruptArchive(let d):
            return .init(title: String(localized: "error.corrupt.title", defaultValue: "壓縮檔結構錯誤"),
                         message: String(localized: "error.corrupt.message", defaultValue: "無法解析壓縮檔（\(d)）。請在電腦上用解壓縮程式確認檔案是否正常。"))
        case .checksumMismatch(let n):
            return .init(title: String(localized: "error.checksum.title", defaultValue: "資料檢查碼不符"),
                         message: String(localized: "error.checksum.message", defaultValue: "「\(n)」解壓後的檢查碼與壓縮檔記錄不一致，這部分資料已損壞。"))
        case .noImages:
            return .init(title: String(localized: "error.noimages.title", defaultValue: "找不到漫畫頁面"),
                         message: String(localized: "error.noimages.message", defaultValue: "壓縮檔中沒有可顯示的圖片（JPEG、PNG、WebP、GIF、HEIC、AVIF）。系統檔與文字檔會被略過。"))
        case .tooManyEntries(let c, let l):
            return .init(title: String(localized: "error.toomany.title", defaultValue: "項目數量過多"),
                         message: String(localized: "error.toomany.message", defaultValue: "壓縮檔有 \(c) 個項目，超過安全上限 \(l)。請拆成多本後再匯入。"))
        case .entryTooLarge(let n, let s, let l):
            return .init(title: String(localized: "error.entrylarge.title", defaultValue: "單一檔案過大"),
                         message: String(localized: "error.entrylarge.message", defaultValue: "「\(n)」解壓後有 \(bytes(Int64(clamping: s)))，超過單頁上限 \(bytes(Int64(clamping: l)))。"))
        case .archiveTooLarge(let s, let l):
            return .init(title: String(localized: "error.archivelarge.title", defaultValue: "檔案過大"),
                         message: String(localized: "error.archivelarge.message", defaultValue: "檔案大小 \(bytes(Int64(clamping: s)))，超過上限 \(bytes(Int64(clamping: l)))。"))
        case .insufficientDiskSpace(let r, let a):
            return .init(title: String(localized: "error.disk.title", defaultValue: "儲存空間不足"),
                         message: String(localized: "error.disk.message", defaultValue: "需要約 \(bytes(r)) 可用空間，目前只有 \(bytes(a))。請刪除不需要的檔案，或到「設定」清除快取後再試。"))
        case .entryNotFound(let i):
            return .init(title: String(localized: "error.notfound.title", defaultValue: "找不到頁面"),
                         message: String(localized: "error.notfound.message", defaultValue: "頁面 \(i + 1) 不存在於壓縮檔中，書籍檔案可能已被更動。"))
        case .cancelled:
            return .init(title: String(localized: "error.cancelled.title", defaultValue: "已取消"),
                         message: String(localized: "error.cancelled.message", defaultValue: "作業已取消，暫存資料已清除。"))
        case .ioError(let d):
            return .init(title: String(localized: "error.io.title", defaultValue: "讀寫錯誤"),
                         message: String(localized: "error.io.message", defaultValue: "存取檔案時發生錯誤（\(d)）。請確認儲存空間足夠後再試。"))
        case .dictionaryTooLarge:
            return .init(title: String(localized: "error.dict.title", defaultValue: "RAR 字典過大"),
                         message: String(localized: "error.dict.message", defaultValue: "這個 RAR 的壓縮字典太大，在這台 iPad 上解壓可能耗盡記憶體，因此不支援。請在電腦上用較小的字典或「儲存」方式重新壓縮後再匯入。"))
        }
    }

    /// Message for a page image that failed to decode.
    static func imageDecodeFailed(_ path: String) -> ErrorExplanation {
        .init(title: L10n.pageLoadFailed,
              message: String(localized: "error.image.message", defaultValue: "「\(path)」不是可解碼的圖片，可能已損壞或使用不支援的格式。仍可繼續翻到其他頁。"))
    }

    static func imageTooLarge(_ w: Int, _ h: Int) -> ErrorExplanation {
        .init(title: L10n.pageLoadFailed,
              message: String(localized: "error.image.large", defaultValue: "圖片尺寸 \(w)×\(h) 像素超過安全上限，為避免記憶體不足而不顯示。"))
    }
}
