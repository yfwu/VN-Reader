import Foundation

extension L10n {
    static let syncReaderBusy = String(localized: "sync.readerbusy", defaultValue: "請先關閉正在閱讀的書籍，再重試同步。")
    static let syncTitle = String(localized: "sync.title", defaultValue: "iCloud 同步")
    static let syncOff = String(localized: "sync.off", defaultValue: "iCloud 同步已關閉")
    static let syncNow = String(localized: "sync.now", defaultValue: "立即同步")
    static let syncWorking = String(localized: "sync.working", defaultValue: "正在同步書庫…")
    static let syncPreparing = String(localized: "sync.preparing", defaultValue: "正在準備書籍識別資料…")
    static let syncUploading = String(localized: "sync.uploading", defaultValue: "正在上傳漫畫，請保持 Wi-Fi 連線…")
    static let syncDownloading = String(localized: "sync.downloading", defaultValue: "正在下載漫畫…")
    static let syncCurrent = String(localized: "sync.current", defaultValue: "這次同步已完成")
    static let syncNoAccount = String(localized: "sync.noaccount", defaultValue: "請登入 iCloud，並允許 VN Reader 使用 iCloud。")
    static let syncAccountChanged = String(localized: "sync.accountchanged", defaultValue: "iCloud 帳號已變更，同步已暫停。請切回原帳號並重新啟動 App；本機書籍仍保留。")
    static let syncQuota = String(localized: "sync.quota", defaultValue: "iCloud 空間不足。請釋出空間後重試；本機書籍仍保留。")
    static let syncNetwork = String(localized: "sync.network", defaultValue: "暫時無法連線，修改已保存在本機。恢復連線後可重試同步。")
    static let syncWaitingForFile = String(localized: "sync.waiting", defaultValue: "漫畫尚未上傳完成，或目前無法取得。請在來源裝置完成同步後重試。")
    static let syncInvalidData = String(localized: "sync.invalid", defaultValue: "雲端資料無法安全讀取，同步已暫停。本機檔案仍保留，請保留備份並回報問題。")
    static let syncLocalFailure = String(localized: "sync.localfailure", defaultValue: "同步狀態無法保存，已停止同步以保護本機資料。請確認裝置空間後重新啟動 App。")
    static let syncCoverOnly = String(localized: "sync.coveronly", defaultValue: "僅封面・開啟時下載")
    static let syncRemoveDownload = String(localized: "sync.removedownload", defaultValue: "移除本機下載")
    static let syncDeleteNotice = String(localized: "sync.deletenotice", defaultValue: "同步書籍目前只支援移除本機下載，雲端原始檔會保留。")
    static let syncFooter = String(localized: "sync.footer", defaultValue: "開啟同步後，啟動或回到 App、切換書籍時會自動同步；可用「立即同步」手動重試。新裝置先取得封面與資訊，開書時才下載原始檔。漫畫傳輸使用 Wi-Fi。關閉同步保留本機與雲端資料；同步書籍僅支援移除本機下載，雲端原始檔會保留。")
    static let syncEnableTitle = String(localized: "sync.enable.title", defaultValue: "開啟 iCloud 同步？")
    static let syncEnable = String(localized: "sync.enable", defaultValue: "開啟並上傳書庫")
    static let syncEnableMessage = String(localized: "sync.enable.message", defaultValue: "漫畫、封面、資訊與閱讀紀錄將上傳到你目前的 iCloud 帳號，並佔用你的 iCloud 空間。請先保留原始漫畫備份。")
    static func syncFailed(_ detail: String) -> String {
        String(localized: "sync.failed", defaultValue: "同步未完成：\(detail)")
    }
}
