import Foundation

/// All user-facing strings. Traditional Chinese is the development language;
/// translations (en, zh-Hans, ja) live in Resources/Localizable.xcstrings.
/// Info.plist sets CFBundleDevelopmentRegion to en, so other system languages
/// fall back to English.
enum L10n {
    // MARK: Library
    static let libraryTitle = String(localized: "library.title", defaultValue: "書庫")
    static let importButton = String(localized: "library.import", defaultValue: "匯入漫畫")
    static let importAccessibility = String(localized: "library.import.a11y", defaultValue: "從「檔案」匯入漫畫")
    static let searchPrompt = String(localized: "library.search", defaultValue: "搜尋書名")
    static let continueReading = String(localized: "library.continue", defaultValue: "繼續閱讀")
    static let emptyTitle = String(localized: "library.empty.title", defaultValue: "書庫是空的")
    static let emptyMessage = String(localized: "library.empty.message", defaultValue: "從「檔案」App 選擇 CBZ 或 CBR 漫畫，匯入後即可離線閱讀。可一次選擇多本。")
    static let noResultsTitle = String(localized: "library.noresults", defaultValue: "沒有符合的書")
    static let guideAdd = String(localized: "guide.add", defaultValue: "加入使用說明")
    static let sortMenu = String(localized: "library.sort", defaultValue: "排序與篩選")
    static let sortRecent = String(localized: "library.sort.recent", defaultValue: "最近閱讀")
    static let sortImported = String(localized: "library.sort.imported", defaultValue: "匯入時間")
    static let sortTitle = String(localized: "library.sort.title", defaultValue: "書名")
    static let filterAll = String(localized: "library.filter.all", defaultValue: "全部")
    static let filterFavorites = String(localized: "library.filter.favorites", defaultValue: "收藏")
    static let statusUnread = String(localized: "status.unread", defaultValue: "未讀")
    static let statusReading = String(localized: "status.reading", defaultValue: "閱讀中")
    static let statusFinished = String(localized: "status.finished", defaultValue: "已讀")
    static func pagesProgress(_ current: Int, _ total: Int) -> String {
        String(localized: "library.pages.progress", defaultValue: "\(current) / \(total) 頁")
    }
    static func pageCount(_ total: Int) -> String {
        String(localized: "library.pages.count", defaultValue: "共 \(total) 頁")
    }
    static let menuMore = String(localized: "book.menu", defaultValue: "更多操作")
    static let menuOpen = String(localized: "book.open", defaultValue: "開啟")
    static let menuReadFromStart = String(localized: "book.fromstart", defaultValue: "從頭閱讀")
    static let menuRename = String(localized: "book.rename", defaultValue: "重新命名")
    static let menuResetProgress = String(localized: "book.reset", defaultValue: "重設閱讀進度")
    static let menuMarkFinished = String(localized: "book.markfinished", defaultValue: "標記為已讀")
    static let menuFavorite = String(localized: "book.favorite", defaultValue: "加入收藏")
    static let menuUnfavorite = String(localized: "book.unfavorite", defaultValue: "取消收藏")
    static let menuDelete = String(localized: "book.delete", defaultValue: "刪除")
    static let menuInfo = String(localized: "book.info", defaultValue: "書籍資訊")
    static let renameTitle = String(localized: "book.rename.title", defaultValue: "重新命名")
    static let renamePlaceholder = String(localized: "book.rename.placeholder", defaultValue: "顯示名稱")
    static func deleteConfirmTitle(_ name: String) -> String {
        String(localized: "book.delete.confirm", defaultValue: "要刪除「\(name)」嗎？")
    }
    static let deleteConfirmMessage = String(localized: "book.delete.message", defaultValue: "只會刪除 App 內的副本、閱讀進度與快取，不會影響你原本的檔案。")
    static let resetConfirmTitle = String(localized: "book.reset.confirm", defaultValue: "要重設閱讀進度嗎？")
    static let sortSeries = String(localized: "library.sort.series", defaultValue: "系列與號碼")

    // MARK: Book info
    static let menuEditInfo = String(localized: "book.info.edit", defaultValue: "編輯資訊")
    static let fieldSeries = String(localized: "info.series", defaultValue: "系列")
    static let fieldNumber = String(localized: "info.number", defaultValue: "號碼")
    static let fieldVolume = String(localized: "info.volume", defaultValue: "卷次")
    static let fieldTitle = String(localized: "info.title", defaultValue: "標題")
    static let fieldWriter = String(localized: "info.writer", defaultValue: "作者")
    static let fieldPenciller = String(localized: "info.penciller", defaultValue: "繪者")
    static let fieldPublisher = String(localized: "info.publisher", defaultValue: "出版社")
    static let fieldYear = String(localized: "info.year", defaultValue: "年份")
    static let fieldSummary = String(localized: "info.summary", defaultValue: "簡介")
    static let hintSeries = String(localized: "info.series.hint", defaultValue: "例：Batman、進擊的巨人")
    static let hintNumber = String(localized: "info.number.hint", defaultValue: "美漫期數 45，或日漫第 3 卷的 3")
    static let hintVolume = String(localized: "info.volume.hint", defaultValue: "美漫系列起始年，例：2016")
    static let hintTitle = String(localized: "info.title.hint", defaultValue: "這一本的標題或卷名")
    static let hintOptional = String(localized: "info.optional", defaultValue: "選填")
    static let infoDetails = String(localized: "info.details", defaultValue: "資訊")
    static let infoFooter = String(localized: "info.footer", defaultValue: "美漫通常用「系列 (起始年) #期數」識別，例如 Batman (2016) #45：同名系列重新從 #1 開始時，以起始年份區分。日漫單行本請把卷數填在「號碼」。資訊只存在 App 的書庫中，不會修改原始檔案。")
    static let generateName = String(localized: "info.name.generate", defaultValue: "依資訊產生")
    static let nameStyleSeriesIssue = String(localized: "info.name.issue", defaultValue: "美漫：系列 (年) #號碼")
    static let nameStyleSeriesVolume = String(localized: "info.name.volume", defaultValue: "日漫：系列 第 N 卷")
    static let nameStyleTitle = String(localized: "info.name.title", defaultValue: "使用標題")
    static func volumeName(_ n: String) -> String {
        String(localized: "info.volume.name", defaultValue: "第 \(n) 卷")
    }
    static func originalFile(_ name: String) -> String {
        String(localized: "info.original", defaultValue: "原始檔名：\(name)")
    }
    static let select = String(localized: "library.select", defaultValue: "選取")
    static let selectAll = String(localized: "library.select.all", defaultValue: "全選")
    static let deselectAll = String(localized: "library.select.none", defaultValue: "取消全選")
    static func selectedCount(_ n: Int) -> String {
        String(localized: "library.selected", defaultValue: "已選取 \(n) 本")
    }
    static func batchTitle(_ n: Int) -> String {
        String(localized: "info.batch.title", defaultValue: "編輯 \(n) 本書")
    }
    static let multipleValues = String(localized: "info.multiple", defaultValue: "多個值")
    static let keepUnchanged = String(localized: "info.keep", defaultValue: "保持不變")
    static let revertField = String(localized: "info.revert", defaultValue: "還原此欄位")
    static let autoNumber = String(localized: "info.autonumber", defaultValue: "依原始檔名順序自動編號")
    static func numberStart(_ n: Int) -> String {
        String(localized: "info.autonumber.start", defaultValue: "從 \(n) 開始")
    }
    static let batchFooter = String(localized: "info.batch.footer", defaultValue: "只會套用你改過的欄位；把欄位清空會刪除該項資訊。簡介請逐本編輯。")
    static func exampleName(_ name: String) -> String {
        String(localized: "info.batch.example", defaultValue: "例：\(name)")
    }

    static let cancel = String(localized: "common.cancel", defaultValue: "取消")
    static let save = String(localized: "common.save", defaultValue: "儲存")
    static let done = String(localized: "common.done", defaultValue: "完成")
    static let close = String(localized: "common.close", defaultValue: "關閉")
    static let retry = String(localized: "common.retry", defaultValue: "重試")
    static let ok = String(localized: "common.ok", defaultValue: "好")
    static let settings = String(localized: "settings.title", defaultValue: "設定")

    // MARK: Import
    static let importWaiting = String(localized: "import.waiting", defaultValue: "等待匯入")
    static let importDownloading = String(localized: "import.downloading", defaultValue: "正在從雲端下載…")
    static let importCopying = String(localized: "import.copying", defaultValue: "正在複製")
    static let importInspecting = String(localized: "import.inspecting", defaultValue: "正在檢查內容")
    static let importCover = String(localized: "import.cover", defaultValue: "正在建立封面")
    static let importFinishing = String(localized: "import.finishing", defaultValue: "即將完成")
    static let importFailed = String(localized: "import.failed", defaultValue: "匯入失敗")
    static let importCancelAction = String(localized: "import.cancel", defaultValue: "取消匯入")
    static let importDismiss = String(localized: "import.dismiss", defaultValue: "移除此訊息")
    static func importDuplicate(_ name: String) -> String {
        String(localized: "import.duplicate", defaultValue: "相同內容已在書庫中（「\(name)」），未重複匯入。")
    }
    static let importSectionTitle = String(localized: "import.section", defaultValue: "匯入狀態")
    static let libraryRecovered = String(localized: "library.recovered", defaultValue: "書庫資料檔讀取失敗，已從最近的備份還原。")

    // MARK: Reader
    static let backToLibrary = String(localized: "reader.back", defaultValue: "返回書庫")
    static let readerSettings = String(localized: "reader.settings", defaultValue: "閱讀設定")
    static let thumbnails = String(localized: "reader.thumbnails", defaultValue: "縮圖")
    static let jumpToPage = String(localized: "reader.jump", defaultValue: "跳頁")
    static let jumpPrompt = String(localized: "reader.jump.prompt", defaultValue: "輸入頁碼")
    static func jumpRange(_ n: Int) -> String {
        String(localized: "reader.jump.range", defaultValue: "1 – \(n)")
    }
    static let go = String(localized: "reader.jump.go", defaultValue: "前往")
    static func pageIndicator(_ p: Int, _ n: Int) -> String {
        String(localized: "reader.page", defaultValue: "\(p) / \(n)")
    }
    static func pageA11y(_ p: Int, _ n: Int) -> String {
        String(localized: "reader.page.a11y", defaultValue: "第 \(p) 頁，共 \(n) 頁")
    }
    static func pageNumber(_ p: Int) -> String {
        String(localized: "reader.page.number", defaultValue: "第 \(p) 頁")
    }
    static let pageSlider = String(localized: "reader.slider", defaultValue: "頁面位置")
    static let previousPage = String(localized: "reader.prev", defaultValue: "上一頁")
    static let nextPage = String(localized: "reader.next", defaultValue: "下一頁")
    static let readingDirection = String(localized: "reader.direction", defaultValue: "閱讀方向")
    static let directionLTR = String(localized: "reader.direction.ltr", defaultValue: "由左至右（美漫、條漫）")
    static let directionRTL = String(localized: "reader.direction.rtl", defaultValue: "由右至左（日漫）")
    static let directionLTRShort = String(localized: "reader.direction.ltr.short", defaultValue: "左→右")
    static let directionRTLShort = String(localized: "reader.direction.rtl.short", defaultValue: "右→左")
    static let fitMode = String(localized: "reader.fit", defaultValue: "頁面顯示")
    static let fitPage = String(localized: "reader.fit.page", defaultValue: "符合整頁")
    static let fitWidth = String(localized: "reader.fit.width", defaultValue: "符合寬度")
    static let layout = String(localized: "reader.layout", defaultValue: "版面")
    static let layoutSingle = String(localized: "reader.layout.single", defaultValue: "單頁")
    static let layoutDouble = String(localized: "reader.layout.double", defaultValue: "雙頁（橫向時）")
    static let layoutVertical = String(localized: "reader.layout.vertical", defaultValue: "垂直捲動")
    static let coverAlone = String(localized: "reader.cover.alone", defaultValue: "封面單獨顯示")
    static let shiftSpread = String(localized: "reader.shift", defaultValue: "雙頁配對位移一頁")
    static let background = String(localized: "reader.background", defaultValue: "閱讀背景")
    static let bgBlack = String(localized: "reader.bg.black", defaultValue: "黑色")
    static let bgGray = String(localized: "reader.bg.gray", defaultValue: "深灰")
    static let bgWhite = String(localized: "reader.bg.white", defaultValue: "白色")
    static let bgSystem = String(localized: "reader.bg.system", defaultValue: "跟隨系統")
    static let pageLoadFailed = String(localized: "reader.page.failed", defaultValue: "此頁無法顯示")
    static let preparingTitle = String(localized: "reader.preparing", defaultValue: "正在準備頁面")
    static func preparingProgress(_ d: Int, _ t: Int) -> String {
        String(localized: "reader.preparing.progress", defaultValue: "已準備 \(d) / \(t) 頁。這本是 solid RAR，必須依序解壓，完成後再次開啟會立即顯示。")
    }
    static let openFailed = String(localized: "reader.open.failed", defaultValue: "無法開啟這本書")
    static let firstPage = String(localized: "reader.first", defaultValue: "已經是第一頁")
    static let lastPage = String(localized: "reader.last", defaultValue: "已經是最後一頁")
    static let bookmarks = String(localized: "reader.bookmarks", defaultValue: "書籤")
    static let addBookmark = String(localized: "reader.bookmark.add", defaultValue: "加入書籤")
    static let removeBookmark = String(localized: "reader.bookmark.remove", defaultValue: "移除書籤")
    static let noBookmarks = String(localized: "reader.bookmarks.empty", defaultValue: "尚無書籤。閱讀時點工具列的書籤按鈕即可加入。")
    static let allPages = String(localized: "reader.allpages", defaultValue: "所有頁面")

    // MARK: Settings
    static let settingsDefaults = String(localized: "settings.defaults", defaultValue: "新書預設值")
    static let settingsDefaultsFooter = String(localized: "settings.defaults.footer", defaultValue: "每本書的設定會分別保存；這裡只影響之後匯入的書。含 ComicInfo.xml 且標示為日漫的書會自動使用由右至左。")
    static let settingsReading = String(localized: "settings.reading", defaultValue: "閱讀")
    static let settingsTapToTurn = String(localized: "settings.tap", defaultValue: "點按左右兩側翻頁")
    static let settingsAnimate = String(localized: "settings.animate", defaultValue: "翻頁動畫")
    static let settingsStorage = String(localized: "settings.storage", defaultValue: "儲存空間")
    static let settingsBooksSize = String(localized: "settings.books.size", defaultValue: "書籍（永久保存）")
    static let settingsCacheSize = String(localized: "settings.cache.size", defaultValue: "快取（可清除）")
    static let settingsClearCache = String(localized: "settings.cache.clear", defaultValue: "清除快取")
    static let settingsCacheFooter = String(localized: "settings.cache.footer", defaultValue: "快取包含縮圖與 solid RAR 的解壓頁面，清除後會在需要時重新產生，不影響書籍與閱讀進度。")
    static let settingsAbout = String(localized: "settings.about", defaultValue: "關於")
    static let settingsVersion = String(localized: "settings.version", defaultValue: "版本")
    static let settingsFormats = String(localized: "settings.formats", defaultValue: "支援格式")
    static let settingsFormatsValue = String(localized: "settings.formats.value", defaultValue: "CBZ（ZIP：儲存／Deflate）、CBR（RAR4／RAR5，含 solid）；圖片：JPEG、PNG、WebP、GIF、HEIC、AVIF。不支援：加密、分卷、7z。")
    static let settingsLicenses = String(localized: "settings.licenses", defaultValue: "第三方授權")
    static let settingsPrivacy = String(localized: "settings.privacy", defaultValue: "VN Reader 不使用網路、帳號、廣告或追蹤。所有書籍只保存在這台裝置上。")
}
