# CI summary

Xcode: Xcode 26.3 Build version 17C529 
iOS Simulator SDK: 26.2
macOS: 15.8.2

- core-macos.log: Executed 53 tests, with 2 tests skipped and 0 failures (0 unexpected) in 2.528 (2.547) seconds
- core-ios.log: Executed 53 tests, with 2 tests skipped and 0 failures (0 unexpected) in 3.806 (4.459) seconds
- ui-ipad-mini: Failed — passed 7, failed 1, skipped 0 — VN iPad mini 6 (26.2)
  - FAIL test01EmptyLibrary(): Failed to get launch progress for <XCUIApplicationImpl: 0x600000c91590 org.yfwu.VNReader at /Users/runner/work/VN-Reader/VN-Reader/build/dd/Build/Products/Debug-iphonesimulator/VNReader.app>: Timed out while requesting launch progress.
  - Failed: test01EmptyLibrary() (73.66677498817444s)
  - Passed: test02ImportAndLibrary() (37.85889410972595s)
  - Passed: test03LTRPagingZoomThumbnailsAndProgress() (148.88760495185852s)
  - Passed: test04RTLAndDirectionSwitchKeepsPage() (56.05600595474243s)
  - Passed: test05ProgressSurvivesBackgroundAndRelaunch() (54.11413896083832s)
  - Passed: test06RenameDeleteAndMenu() (33.087952971458435s)
  - Passed: test07RepeatedOpenClose() (65.7289570569992s)
  - Passed: test08VerticalScrollMode() (60.91785490512848s)
- ui-ipad-pro: Failed — passed 7, failed 1, skipped 0 — VN iPad Pro 13 (26.2)
  - FAIL test08VerticalScrollMode(): XCTAssertTrue failed
  - Passed: test01EmptyLibrary() (93.05823194980621s)
  - Passed: test02ImportAndLibrary() (26.949565052986145s)
  - Passed: test03LTRPagingZoomThumbnailsAndProgress() (139.58889603614807s)
  - Passed: test04RTLAndDirectionSwitchKeepsPage() (62.9625129699707s)
  - Passed: test05ProgressSurvivesBackgroundAndRelaunch() (45.919180035591125s)
  - Passed: test06RenameDeleteAndMenu() (36.31755602359772s)
  - Passed: test07RepeatedOpenClose() (71.17736196517944s)
  - Failed: test08VerticalScrollMode() (24.28320801258087s)

## Device build

```
File: VNReader-0.1.0-1-UNSIGNED.ipa
Signing: UNSIGNED — cannot be installed on a device as-is
Platform: iphoneos (arm64)
Bundle ID: org.yfwu.VNReader
Version: 0.1.0 (1)
Minimum OS: 18.0
Archs: arm64
Built with: Xcode 26.3 Build version 17C529 
SDK: 26.2
Date: 2026-11-04T19:20:55Z
Commit: f8bfcbe
Size: 1.6M
```
