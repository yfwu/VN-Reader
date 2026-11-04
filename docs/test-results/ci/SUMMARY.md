# CI summary

Xcode: Xcode 26.3 Build version 17C529 
iOS Simulator SDK: 26.2
macOS: 15.8.2

- core-macos.log: Executed 53 tests, with 2 tests skipped and 0 failures (0 unexpected) in 3.259 (3.282) seconds
- core-ios.log: Executed 53 tests, with 2 tests skipped and 0 failures (0 unexpected) in 3.003 (3.040) seconds
- ui-ipad-mini: Failed — passed 3, failed 4, skipped 0 — VN iPad mini 6 (26.2)
  - FAIL test03LTRPagingZoomThumbnailsAndProgress(): XCTAssertEqual failed: ("15") is not equal to ("16")
  - FAIL test04RTLAndDirectionSwitchKeepsPage(): XCTAssertTrue failed
  - FAIL test05ProgressSurvivesBackgroundAndRelaunch(): failed - expected page 3, got 2
  - FAIL test07RepeatedOpenClose(): XCTAssertTrue failed
  - Passed: test01EmptyLibrary() (26.710551023483276s)
  - Passed: test02ImportAndLibrary() (17.031221985816956s)
  - Failed: test03LTRPagingZoomThumbnailsAndProgress() (87.67978894710541s)
  - Failed: test04RTLAndDirectionSwitchKeepsPage() (39.88375008106232s)
  - Failed: test05ProgressSurvivesBackgroundAndRelaunch() (21.87879192829132s)
  - Passed: test06RenameDeleteAndMenu() (32.144306898117065s)
  - Failed: test07RepeatedOpenClose() (24.01086401939392s)
- ui-ipad-pro: Failed — passed 6, failed 1, skipped 0 — VN iPad Pro 13 (26.2)
  - FAIL test03LTRPagingZoomThumbnailsAndProgress(): XCTAssertEqual failed: ("15") is not equal to ("16")
  - Passed: test01EmptyLibrary() (84.76276302337646s)
  - Passed: test02ImportAndLibrary() (29.710134029388428s)
  - Failed: test03LTRPagingZoomThumbnailsAndProgress() (106.20135402679443s)
  - Passed: test04RTLAndDirectionSwitchKeepsPage() (64.53134596347809s)
  - Passed: test05ProgressSurvivesBackgroundAndRelaunch() (45.76389396190643s)
  - Passed: test06RenameDeleteAndMenu() (42.86511194705963s)
  - Passed: test07RepeatedOpenClose() (75.61381602287292s)

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
Date: 2026-11-04T18:32:37Z
Commit: 6cc8b26
Size: 1.6M
```
