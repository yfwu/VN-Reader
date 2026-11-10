# VN Reader 書庫設計：Metadata、iCloud 與 Mac

狀態：2026-11-07 的長期設計草案，保留作為規劃依據。2026-11-10 已分成 build 6 的修復／Catalyst 發布與 build 7 的選用 CloudKit 原型；下文的完整設計不代表已交付功能，工時仍為原始粗估。

Build 7 的實作範圍、遷移方式與驗證狀態以 [ICLOUD_BUILD7_TEST_PLAN.md](ICLOUD_BUILD7_TEST_PLAN.md) 為準。原型採用 SHA-256 身分、CKSyncEngine 輕量書目區與獨立 CKAsset 原檔區；進度目前與 metadata 共用 Book payload，沒有最近刪除、雲端永久刪除、批次預覽／復原、WebDAV 或獨立 Progress record。驗證失敗會停止同步並保留本機資料，不會略過資料後繼續推進 token。

## 1. 目標

VN Reader 要從離線閱讀器變成「漫畫儲藏書庫」：在一處上傳，所有裝置都看得到，每本書可選擇下載或只留封面。

| 代號 | 目標 |
|---|---|
| G1 | 在任一裝置匯入的書，其他裝置都看得到封面與資訊，空間由使用者自己的 iCloud 負擔 |
| G2 | 每台裝置可逐本決定保留下載或只留封面 |
| G3 | 進度、書籤、最愛與 metadata 跨裝置同步，離線修改不會互相蓋掉 |
| G4 | 批次編輯能預覽、能復原，並涵蓋 metadata 以外的動作（下載、刪除、匯出） |
| G5 | Mac 版與 iCloud 同一次發布 |
| G6 | 不使用 iCloud 的人，功能維持現狀且完全離線 |
| G7 | App 成為唯一保存處之後，書不會因誤操作或同步問題而遺失 |

**第一版不做：** 書庫分享與多人協作、修改壓縮檔本身、線上 metadata 抓取（ComicVine、Bangumi 等）、邊下載邊閱讀、WebDAV（第 11 節保留接口）。

## 2. 現況與限制

| 現況 | 位置 | 影響 |
|---|---|---|
| `library.json` 整份覆寫 | [`LibraryDatabase`](../Packages/ComicCore/Sources/ComicCore/Library/LibraryDatabase.swift) | 無法逐欄位合併。每筆約 1 KB，2 萬本約 20 MB，加上同步資訊會更大 |
| `BookRecord.id` 是匯入時隨機產生的 UUID | [`BookRecord`](../Packages/ComicCore/Sources/ComicCore/Library/BookRecord.swift) | 同一本書在各裝置 ID 不同 |
| `fingerprint` 只有 CRC-32 加檔案大小 | [`BookImporter`](../Packages/ComicCore/Sources/ComicCore/Import/BookImporter.swift) | 夠用於本機查重，不適合當永久跨裝置身分 |
| 「只有完整匯入才有紀錄」，閱讀流程假設書檔一定在本機 | `BookImporter`、[`ReaderViewModel.open`](../App/Sources/Reader/ReaderViewModel.swift) | 只留封面需要新的狀態 |
| 進度與書籤是 manifest 的頁碼 | `ReadingProgress`、[`PageManifest`](../Packages/ComicCore/Sources/ComicCore/Pages/PageManifest.swift) | manifest 必須跨裝置一致 |
| `saveInfo` 整包覆蓋 metadata，`batchEdit` 則是逐欄位 | [`LibraryStore`](../App/Sources/Model/LibraryStore.swift) | 需統一成一條修改路徑 |
| 刪除是立即且永久的 | `LibraryStore.delete` | 違反 G7 |
| 選取模式只有「編輯資訊」，且改完不能復原 | [`LibraryView`](../App/Sources/Library/LibraryView.swift) | G4 不足 |
| ComicCore 可在 Linux 建置，CI 也在 Linux 跑測試 | `.github/workflows/ios.yml` | ComicCore 不能依賴 CloudKit |
| 沒有 entitlements 檔，App Sandbox 為關閉 | `Config/App.xcconfig` | Mac 與 iCloud 都要新增 |

## 3. 關鍵決策

| # | 決策 | 理由 |
|---|---|---|
| D1 | **閱讀器永遠只讀本機 `Books/<id>/`。** 遠端只負責把檔案搬進搬出 | `BookPageSource`、ZIP、RAR 全部不用改；「保留下載」由 App 自己控制；iCloud 與 WebDAV 可共用同一介面 |
| D2 | 每本書分三層：紀錄、輕量資產（封面、manifest）、書檔 | 只留封面時，前兩層永遠在 |
| D3 | 紀錄用 CKSyncEngine，存在 private database 的自訂 zone | 支援 iOS 17 與 Catalyst 17 以上，會處理排程、推播與暫時性錯誤 |
| D4 | 書檔走 `RemoteBookStore` 介面，**暫定用 CKAsset，備案是 iCloud Documents**，由 Phase 0 決定 | 見 3.1 |
| D5 | 永久身分是原始檔的 SHA-256（`contentID`），匯入後永不改變 | 兩台裝置各自匯入同一本時會自然合併成一筆 |
| D6 | 不修改壓縮檔。ComicInfo 只做匯出 | 檔案不變才能維持 D5。CBR 也無法寫回 |
| D7 | 逐欄位 last-writer-wins，時間用 hybrid logical clock | 一個人使用多台裝置，不需要更複雜的模型；裝置時鐘不準也能收斂 |
| D8 | 刪除先進「最近刪除」，保留 30 天 | G7 |
| D9 | 尚未確認上傳成功的書，不能移除本機檔 | G7 |
| D10 | Mac 版用 Mac Catalyst，與 iPad 共用 bundle ID | 保留約 2,400 行閱讀與影像程式碼。Apple 的 Universal Purchase 說明表示 Catalyst 可與 iOS 共用 bundle ID |
| D11 | 同步邏輯分兩層：純合併邏輯放 ComicCore，CloudKit 放 `App/Sources/Sync` | 合併邏輯可在 Linux 上做單元測試 |

### 3.1 書檔後端：CKAsset 或 iCloud Documents

這裡更正先前的建議。我原本建議用 iCloud Documents，但查證後改為暫定 CKAsset：

| | CKAsset（暫定） | iCloud Documents（備案） |
|---|---|---|
| 大小上限 | Apple 工程師於 2026 年 5 月在論壇表示每個 asset 可達 50 GB。正式文件沒有寫，舊文件的 50 MB 據稱只適用 Web Services | 未查到相關限制 |
| 空間不足 | 有明確的 `CKError.quotaExceeded` | 未查到等價的明確錯誤，需實測 |
| 保留下載 | 由 D1 控制，App 自己決定檔案去留 | 找不到 App 層級的 pin API，系統可能自行清除。論壇上有人回報多年無解 |
| 進度 | 由 CKOperation 回報，需實測大檔 | 第三方文章指出上傳進度只有 0 或 100；iOS 18.4 起有下載狀態不更新的回報，Apple 未回應 |
| 背景傳輸 | **未知，最大風險**。有 long-lived operation，但文件沒有寫期限與續傳行為 | 由系統服務處理，應該較強 |
| 磁碟用量 | 上傳時直接讀本機檔；下載先到 staging，要馬上移走 | 容器與 `Books/` 可能同時各有一份 |
| 前提 | 使用者對此 App 開啟 iCloud | 使用者還要開啟 iCloud Drive |

**切換條件：** 若 Phase 0 顯示 3 GB 的書無法在合理條件下完成上傳，且中斷後無法接續，就改用 iCloud Documents，再由 D1 解決保留下載的問題（下載後複製到 `Books/`，然後 evict 容器內的檔案）。無論選哪一個，第 5 節以上的設計都不變。

## 4. 資料模型

### 4.1 身分

```swift
struct BookRecord {
    var id: UUID                // 每台裝置自己的主鍵，也是 Books/<id>/ 的資料夾名
    var contentID: String?      // 原始檔 SHA-256 hex；舊書在開啟 iCloud 時補算
    var fingerprint: String     // 保留，供尚未補算的舊書查重
    ...
}
```

- 資料夾名稱不動，舊書不用搬檔案。
- 同步時用 `contentID` 對應本機 `id`。CloudKit 的 record name 是 `book-<contentID>`，所以兩台裝置匯入同一本時，寫到的是同一筆。
- 雜湊在 `stageFile` 既有的 1 MB 迴圈內一起計算，記憶體用量不變。Apple 平台用 CryptoKit，Linux 用 ComicCore 內建實作，以確保不新增依賴。
- 收到 `contentID` 後必須驗證為 64 位 hex。雲端字串一律不當檔案路徑。

### 4.2 欄位分類

| 類別 | 欄位 | 同步 | 合併方式 |
|---|---|---|---|
| 不可變 | `contentID`、`originalFileName`、`format`、`isSolid`、`fileSize`、`pageCount`、`importedAt` | 是 | 建立時寫入，不再變動 |
| 書籍資訊 | `displayName`、全部 metadata、`isFavorite`、`readingDirection` | 是 | 逐欄位 LWW |
| 刪除狀態 | `trashedAt` | 是 | LWW，還原就是寫入 nil |
| 上傳狀態 | `fileAvailable` | 是 | LWW，由上傳完成的裝置寫入 |
| 進度 | `currentPage`、`lastReadAt`、`finished` | 是 | 三者視為一組 LWW，新增獨立的 `updatedAt`，因為「重設進度」會清掉 `lastReadAt` |
| 書籤 | `bookmarks` | 是 | 每個頁碼一個 LWW 開關，移除時保留紀錄 |
| 裝置設定 | `fitMode`、`layout`、`keepDownloaded`、本機檔案狀態 | **否** | 雙頁或單頁取決於螢幕，不跨裝置 |

Tag 這類清單欄位也是整欄 LWW，兩台裝置同時改同一本的 tag 時，只有一邊會留下。一個人使用的情境下可以接受，換來的是模型簡單很多。

### 4.3 合併邏輯（ComicCore）

```swift
struct Stamp: Codable, Comparable { var ms: Int64; var counter: UInt32; var device: String }
struct Register<T: Codable>: Codable { var value: T?; var stamp: Stamp }

struct SyncedBook: Codable {
    var schema: Int
    var contentID: String
    var immutable: BookFacts
    var fields: [String: Register<String>]   // displayName、metadata、favorite 等，以字串為 key
    var trashedAt: Register<Date>
    var fileAvailable: Register<Bool>
}

struct SyncedProgress: Codable {
    var progress: Register<ReadingProgress>
    var bookmarks: [Int: Register<Bool>]
}

extension SyncedBook { func merged(with other: SyncedBook) -> SyncedBook }
```

- `Stamp` 是 hybrid logical clock，取 `max(牆鐘, 最後見過的 ms)`。同毫秒時 counter 加一，最後以 `device` 決勝。
- **`fields` 用字串 key，合併時保留看不懂的 key。** 這樣舊版 App 不會把新版欄位吃掉，在 TestFlight 版本混用時很重要。
- `merged` 必須滿足交換律、結合律與冪等律，第 10 節用測試保證。
- **舊資料遷移：** metadata 的 stamp 設為最小值，同分時非空值優先，再比 `device`。進度的 stamp 取 `lastReadAt`。

Phase 1 起，即使 iCloud 沒開也要寫入 stamp，之後才能正確合併。

### 4.4 本機儲存

```
<root>/library.json              schema v2，舊欄位不變，新增的都有預設值
<root>/Books/<id>/manifest.json  永遠存在
<root>/Books/<id>/cover.jpg      永遠存在
<root>/Books/<id>/book.cbz|cbr   可不存在
<root>/Sync/engine-state         CKSyncEngine 狀態，必須自行保存
<root>/Sync/records.json         CKRecord system fields
<root>/Sync/uploads.json         上傳佇列
<root>/edit-history.json         最近 20 次批次修改
```

`library.json` 仍每次整份覆寫，頻繁存進度時會成為瓶頸。Phase 0 要實測 2 萬本的寫入成本，太高就把進度拆到 `progress.json`。第 12 節的目標書庫大小會影響這個判斷。

## 5. 書的狀態

狀態由「本機有無檔案」與「遠端有無檔案」推導，不另外存一個會失準的欄位。

| 本機檔 | 遠端 | 狀態 | 書籍格顯示 | 可做的事 |
|---|---|---|---|---|
| 有 | iCloud 關閉 | 僅本機 | 無標記 | 閱讀 |
| 有 | 等待或上傳中 | 上傳中 | 上傳進度 | 閱讀，**不能移除下載** |
| 有 | 已確認 | 已下載 | 無標記，保留下載時有圖示 | 閱讀、移除下載 |
| 無 | 已確認 | 只留封面 | 雲朵圖示 | 下載、開啟時自動下載 |
| 下載中 | 已確認 | 下載中 | 進度 | 取消 |
| 無 | 尚未上傳 | 等待來源裝置 | 灰階，說明來源裝置尚未上傳完成 | 只能看資訊 |

紀錄通常比書檔先到，所以「等待來源裝置」是正常狀態，不是錯誤。

## 6. 同步設計

### 6.1 CloudKit 結構

| Zone | Record | 內容 | 由誰同步 |
|---|---|---|---|
| `Library` | `Book`（`book-<contentID>`） | `SyncedBook` JSON、封面 asset、manifest asset | CKSyncEngine |
| `Library` | `Progress`（`progress-<contentID>`） | `SyncedProgress` JSON | CKSyncEngine |
| `BookFiles` | `BookFile`（`file-<contentID>`） | 書檔 asset、大小 | 手動的 CKOperation |

- **用 JSON 欄位：** 新增 metadata 不必改 CloudKit schema，第 4.3 節的向前相容也靠這點。代價是無法在 Dashboard 查詢，這裡用不到。
- **`Progress` 分開存：** 翻頁寫入不會牽動 `Book`。
- **`BookFiles` 分開存：** CKAsset 預設會隨紀錄下載，所以在 `nextFetchChangesOptions` 回傳 `.allExcluding([BookFiles])`，並只在需要時用 `CKFetchRecordsOperation` 抓取。Phase 0 要確認自動同步也遵守這個範圍。
- 批次修改 5,000 本約需 20 個請求，因為 CKSyncEngine 每批上限 250 筆。用 `RecordZoneChangeBatch(pendingChanges:recordProvider:)` 自動分批。
- 進度不必每頁送出：更新待送清單，在關閉閱讀器與進入背景時呼叫 `sendChanges`。

### 6.2 主要流程

**匯入：** 寫入 `Books/<id>/`，加入書庫，排入 `Book` 與 `Progress`，再排入上傳佇列。上傳前先用不含 asset 的 `desiredKeys` 檢查 `file-<contentID>`，已存在就跳過。

**上傳：** 一次一本，佇列持久化，預設僅 Wi-Fi。上傳成功後把 `fileAvailable` 寫成 true。

**收到新書：** 把封面與 manifest 從 staging 移到 `Books/<id>/`（staging 會被系統清除），然後建立紀錄。`contentID` 相同的本機書直接合併。

**下載：**
1. 用 `DiskSpacePolicy` 檢查空間，下載到 `tmp`。
2. 計算 SHA-256，與 `contentID` 比對，不符就丟棄並回報。
3. 原子搬到 `Books/<id>/`，然後才允許開啟。

**開啟書：** `ReaderViewModel.open` 先確認本機有檔，沒有就下載，沿用「正在準備頁面」卡片的形式顯示進度與取消。

**移除下載：**
1. 重新向伺服器確認 `file-<contentID>` 存在且大小相符。
2. 確認後呼叫新增的 `StorageMaintenance.removeDownload`，刪除書檔與 `Extracted` 快取，保留 `cover.jpg` 與 `manifest.json`。
3. 這本書正開著時不允許移除。

**衝突：** 收到 `serverRecordChanged` 時，CKSyncEngine 不會代為處理。App 要用伺服器版本解 JSON、呼叫 `merged`，再重新送出。

**刪除：** 寫入 `trashedAt`，書移到「最近刪除」，所有裝置同步。檔案與紀錄保留 30 天。到期後由任一台裝置刪除 `BookFile`、`Book`、`Progress`。「永久刪除」要明確確認。

**重新匯入已刪除的書：** 相同 `contentID` 視為還原。

### 6.3 帳號與開關

- iCloud 由使用者主動開啟，第一次要清楚說明會佔用多少 iCloud 空間。新安裝也一樣，不自動上傳。
- 開啟後的順序：補算 `contentID`（有進度條、可中斷）→ 同步紀錄 → 上傳本機書。
- **登出 iCloud：** 停止同步，本機書全部保留；只留封面的書顯示為無法使用。
- **切換帳號：** 收到 `accountChange` 後暫停，由使用者決定。不把兩個帳號的書庫自動合併，也不自動刪除本機檔案。
- **關閉 iCloud：** 只停止同步，不動雲端資料。「刪除 iCloud 上的書庫」是另一個需要確認的動作。
- **空間已滿：** 暫停佇列並持續顯示橫幅，書保留在本機。紀錄也可能無法寫入，所以兩者都要顯示狀態，不能靜默失敗。

### 6.4 下載策略

每台裝置設定一次，預設「開啟時下載」：

- **開啟時下載：** 預設值，新裝置只有封面。
- **全部下載：** 給 Mac 這種大容量裝置，讓它成為完整備份。

單本或批次可設「保留下載」。自動清理最久沒讀的書留到第一版之後。

### 6.5 雲端資料的信任邊界

雲端的內容視同外部輸入：JSON 解碼失敗只略過該筆並記錄；manifest 開啟時驗證 `archiveIndex` 範圍；頁碼沿用 `recordPosition` 的上下限檢查；檔案路徑只用本機 UUID。

## 7. Metadata 與批次編輯

### 7.1 欄位

現有欄位不變，依 ComicInfo 擴充：

| 類型 | 新增欄位 |
|---|---|
| 創作者 | inker、colorist、letterer、coverArtist、translator、editor |
| 出版 | imprint、month、day、count、languageISO、ageRating |
| 分類（清單） | genre、tags、storyArc、characters |

`MetadataField` 擴充即可，清單欄位以逗號分隔，與 ComicInfo 的慣例相同。匯入時解析新欄位。舊書提供批次動作「從 ComicInfo 重新讀取」，需要本機有檔案。

### 7.2 修改操作

所有修改都走同一條路徑，`saveInfo` 也改成這樣：

```swift
enum MetadataOperation {
    case set(MetadataField, String)            // 空字串代表清除
    case findReplace(MetadataField, find: String, replace: String, regex: Bool)
    case addValue(MetadataField, String)
    case removeValue(MetadataField, String)
    case number(start: Int, step: Int, order: BookOrder)
    case parseFileName(FileNamePattern)
    case generateName(BookNameStyle)
    case reloadComicInfo
}

struct BookChange { var bookID: UUID; var before: [String: String?]; var after: [String: String?] }

enum MetadataEditor {
    /// 純函式：只計算結果，預覽與實際套用用同一份結果。
    static func plan(_ ops: [MetadataOperation], books: [BookRecord]) -> [BookChange]
}
```

- **先預覽再套用：** 畫面顯示前後差異，沒有變動的書不列入。
- **復原：** 保留最近 20 次的 `before`，跨重開機。復原是一次新的修改，有新的 stamp，同步時不會被舊資料蓋回。
- **檔名解析：** 內建 `{series} #{number} ({year})`、`{series} v{volume} c{number}`、`{series} 第{number}卷`，並可自訂。預覽時標出解析失敗的書，不會寫入半套資料。
- **中文數字：** 「第十二卷」要能解析成 12。

### 7.3 介面

- **iPad：** 保留 [`BatchInfoView`](../App/Sources/Library/BookInfoView.swift)，加入新操作與預覽頁。
- **表格模式：** 螢幕夠寬時用 SwiftUI `Table`，可排序、可直接改儲存格。iPad mini 直向這類窄版面仍用表單。
- **選取工具列：** 新增編輯資訊、下載、移除下載、保留下載、最愛、標記已讀或未讀、匯出、刪除。
- **書庫：** 新增系列分組檢視（從 `series` 推導，不是新實體），以及「缺系列」「缺編號」「重複書名」與 tag、作者篩選。

### 7.4 匯出

- **匯出原始檔：** 單本或批次，檔名用 `originalFileName`，不在本機的先下載。這是 G7 的出口。
- **匯出 ComicInfo：** 匯出 `.xml` 旁車檔，或輸出一份新的 CBZ 到 App 之外。書庫內的檔案不變。寫 CBZ 需要新的 ZIP 寫入器，排在第一版之後。

## 8. Mac 版

| 項目 | 做法 |
|---|---|
| 建置 | `SUPPORTS_MACCATALYST = YES`，`TARGETED_DEVICE_FAMILY` 加入 Mac，關閉 Derive Mac Catalyst Product Bundle Identifier 以共用 bundle ID，新增 entitlements，開啟 App Sandbox。最低版本隨 iOS 18 對應 macOS 15，以 Xcode 實際結果為準 |
| 介面 | 第一版用「Scale Interface to Match iPad」，較省工；Phase 5 看實際效果再評估 Optimize for Mac |
| 翻頁 | 方向鍵與空白鍵沿用，新增滾輪或觸控板翻頁 |
| 放大鏡 | 長按不適合滑鼠，改用右鍵選單或快捷鍵開啟 |
| 選單列 | 匯入、閱讀導覽、顯示模式、書庫檢視 |
| 匯入 | 支援從 Finder 拖入整個資料夾，遞迴尋找書檔 |
| 批次編輯 | 表格模式是主要介面，支援 Cmd-A、Shift 區間選取 |

Phase 0 要確認 CUnrar 能在 Catalyst 建置，以及 iPad 與 Mac 能使用同一個 CloudKit container。

## 9. 專案與發布

- **Capabilities：** iCloud（CloudKit）、Push Notifications，加上 Background Modes 的 remote notifications。CKSyncEngine 需要前兩項。
- **CloudKit schema：** TestFlight 與 App Store 版使用 Production 環境，發布前要把 schema 部署上去，否則開發時正常，測試者卻無法同步。
- **文件：** 更新 [PRIVACY.md](PRIVACY.md)、README、ARCHITECTURE。「不連線、資料只在裝置上」要改寫為：資料在使用者自己的 iCloud，開發者沒有伺服器，也讀不到內容。App Store 的隱私標示要在送審前重新確認。
- **在地化：** 新字串一律依 [AGENTS.md](../AGENTS.md) 放進 `L10n.swift` 與 `Localizable.xcstrings`，包含四種語言。

## 10. 測試

| 層級 | 內容 | 環境 |
|---|---|---|
| 合併邏輯 | `merged` 的交換律、結合律、冪等律（隨機產生資料）；未知 key 保留；時鐘倒退 | Linux、macOS CI |
| 雙裝置模擬 | 用假的 transport 與 `RemoteBookStore`，跑完匯入、離線修改、合併、刪除、還原 | Linux、macOS CI |
| 遷移 | v1 `library.json` fixture 升到 v2，資料不遺失 | Linux、macOS CI |
| 批次編輯 | `plan` 的預覽與實際結果一致；復原；檔名解析 | Linux、macOS CI |
| UI | 選取、預覽、狀態標記、最近刪除 | 模擬器 |
| 實機 | Mac 加 iPad mini，見下方驗收清單 | 真實 iCloud 帳號 |

### 驗收清單

1. Mac 匯入 3 GB 的書，iPad 先看到封面，上傳完成後可下載閱讀，SHA-256 相符。
2. 兩台裝置都離線，同時修改同一本的不同欄位，上線後兩邊的修改都保留。
3. 兩台裝置離線匯入同一本書，上線後只有一筆，只上傳一次。
4. iPad 讀到 50 頁關閉，Mac 開啟時位於第 50 頁。
5. 上傳途中殺掉 App、斷網、進入背景，書不遺失，之後能繼續或重來。
6. iCloud 空間已滿時有明確提示，本機書可正常閱讀。
7. 上傳未完成時無法移除下載。
8. 在 Mac 刪除一本，iPad 同步消失；30 天內可還原；還原後進度與書籤都在。
9. 登出 iCloud、切換帳號後，本機檔案都還在。
10. 下載途中空間不足，有明確提示且不留下殘檔。
11. 關閉 iCloud 的使用者，所有現有功能與測試結果不變。
12. 新舊版 App 混用時，新版欄位不被舊版清掉。

## 11. WebDAV 保留接口

WebDAV 是給進階使用者的額外選項，不是同步後端，現在只需要這個介面：

```swift
protocol RemoteBookStore: Sendable {
    func exists(_ contentID: String) async throws -> RemoteFileInfo?
    func upload(_ local: URL, contentID: String, progress: @Sendable (Double) -> Void) async throws
    func download(_ contentID: String, to: URL, progress: @Sendable (Double) -> Void) async throws
    func delete(_ contentID: String) async throws
}
```

`CloudKitBookStore` 是第一個實作。之後的 WebDAV 分兩種用法，都不影響閱讀流程：

- **來源：** 瀏覽 WebDAV 目錄，下載後走現有匯入。
- **存放位置：** 書檔放 NAS，封面與紀錄照樣走 iCloud。帳密存在各裝置的 Keychain，不同步。

邊讀邊串流不在範圍內：CBR 一定要完整下載，而且它會破壞 D1。

## 12. 待 owner 決定

| # | 問題 | 我的預設 | 影響 |
|---|---|---|---|
| Q1 | 目標書庫有多大？ | 2 萬本 | `library.json` 是否要拆分、封面佔用多少空間 |
| Q2 | iPhone 要包含在這個里程碑嗎？ | 不包含。目前只支援 iPad，iPhone 版面尚未開始，這本身就是獨立工作 | 「其他設備」的範圍與時程 |
| Q3 | 最近刪除保留多久？ | 30 天 | 雲端空間的佔用時間 |
| Q4 | 新裝置預設只留封面嗎？ | 是，每台裝置可改為全部下載 | 第 6.4 節 |
| Q5 | 匯入上限維持 8 GB 嗎？ | 維持 | 上傳時間與 Phase 0 的測試條件 |
| Q6 | 同步要不要包含閱讀器的 App 設定？ | 不包含 | 範圍 |

## 13. 實作階段

| 階段 | 內容 | 完成條件 | 粗估 |
|---|---|---|---|
| **0 原型驗證** | 見下方 | 決定 D4，確認 Catalyst 可行 | 2–3 天 |
| **1 Metadata** | schema v2、stamp、`contentID`、`MetadataOperation`、預覽、復原、新欄位、檔名解析、表格模式 | 可單獨發給測試者 | 2–3 週 |
| **2 資料安全** | 最近刪除、匯出原始檔、批次動作、書的狀態模型 | 可單獨發給測試者，iCloud 仍未啟用 | 約 1 週 |
| **3 紀錄同步** | `SyncedBook` 合併、CKSyncEngine、封面與 manifest、帳號處理 | 內部測試 | 2–3 週 |
| **4 書檔同步** | `RemoteBookStore`、上傳佇列、下載、移除下載、設定頁 | 內部測試 | 2–3 週 |
| **5 Mac** | Catalyst、選單、滑鼠操作、資料夾匯入 | 與階段 3、4 一起發布 | 1–2 週 |
| **6 試用** | 跑完驗收清單，測試者實機使用 | 驗收清單全部通過 | 至少 2 週 |
| **7 WebDAV** | 來源，之後才是存放位置 | 獨立發布 | 另估 |

階段 1、2 不依賴 iCloud，可先交付。階段 3–5 開發時可先後進行，但**對外是同一次發布**。

### Phase 0 要回答的問題

| 問題 | 通過條件 | 失敗時 |
|---|---|---|
| 3 GB CKAsset 上傳與下載 | 在家用 Wi-Fi 下完成，有進度回報 | 換 iCloud Documents |
| 上傳中進入背景、殺掉 App、斷網 | long-lived operation 能續傳，或可從佇列重來 | 換 iCloud Documents |
| `.allExcluding` 是否阻止書檔自動下載 | 第二台裝置不會自動下載 `BookFiles` | 換 iCloud Documents，或調整 zone 結構 |
| iPad 與 Catalyst 共用 bundle ID 與 container | 能簽署，兩邊讀到同一份資料 | 重新評估 D10 |
| CUnrar 能以 Catalyst 建置 | 可建置並通過開書測試 | 修正建置設定 |
| 2 萬本 `library.json` 的寫入成本 | 不影響翻頁 | 拆出 `progress.json` |
| 封面與 manifest 的實際大小 | 2 萬本首次同步的空間與時間可接受 | 降低封面解析度 |

## 14. 主要風險

| 風險 | 嚴重度 | 緩解 |
|---|---|---|
| 同步錯誤導致書遺失 | 高 | D8、D9、下載驗證 SHA-256、不自動刪本機檔、匯出原始檔 |
| 大檔背景傳輸不穩 | 高 | Phase 0、D4 的備案、持久化佇列 |
| 合併錯誤覆蓋使用者修改 | 中 | 合併是純函式並有性質測試，復原走新 stamp |
| CloudKit schema 沒部署到 Production | 中 | 發布檢查清單 |
| 書庫太大時 JSON 與畫面變慢 | 中 | Phase 0 實測，必要時拆檔或改 SQLite |
| Apple 服務行為無法從文件得知 | 中 | 核心流程都依賴實測，不依賴論壇說法 |

## 15. 參考資料

皆於 2026-11-07 查閱全文。論壇與第三方文章僅作線索，相關行為都列入 Phase 0 實測。

**Apple 文件**
- [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)：平台支援、entitlements、狀態保存、每批 250 筆、衝突需自行處理、帳號事件。
- [CKSyncEngineDelegate nextFetchChangesOptions](https://developer.apple.com/documentation/cloudkit/cksyncenginedelegate-1q7g8/nextfetchchangesoptions(_:syncengine:))、[FetchChangesOptions.Scope](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5/fetchchangesoptions/scope-swift.enum)：可排除特定 zone。
- [CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset)：staging 區、`desiredKeys`、以清空欄位的方式讓 asset 成為孤兒後回收。
- [CloudKit Web Services 資料大小限制](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/PropertyMetrics.html)：record 1 MB、asset 50 MB，頁面為 2016 年的舊文件。
- [isLongLived](https://developer.apple.com/documentation/cloudkit/ckoperation/configuration-swift.class/islonglived)：頁面只有屬性定義，沒有行為說明。

**Apple Developer Forums**
- [CKAsset 大小限制](https://developer.apple.com/forums/thread/827897)：Apple Frameworks Engineer 回覆 50 GB（2026 年 5 月），沒有引用正式文件。
- [如何避免 iCloud Drive 檔案被清除](https://developer.apple.com/forums/thread/104356)：提問者表示沒有解法，Apple 未回應。
- [iOS 18.4 起的 iCloud Drive 行為變更](https://developer.apple.com/forums/thread/785030)：單一開發者回報，Apple 未回應。
- [Universal Purchase：macOS + iOS](https://developer.apple.com/forums/thread/751188)：貼文引用 Apple 說明，指 Xcode 11.4 起 Catalyst 可共用 bundle ID。原始說明頁未直接查閱。
- [Universal Purchase 問題](https://developer.apple.com/forums/thread/128745)：開發者回報 Mac Catalyst 的 provisioning profile 帶 `maccatalyst.` 前綴與 App ID 簽署錯誤，沒有確認的解法。Phase 0 要實際驗證簽署。

**第三方**
- [Advanced iCloud Documents](https://fatbobman.com/en/posts/advanced-icloud-documents/)（fatbobman，2023 年 12 月）：placeholder、evict、進度行為。
