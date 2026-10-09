# Kế hoạch tích hợp QA Desk vào AMC và làm lại giao diện

Ngày: 2026-10-01, cập nhật 2026-10-02. Trạng thái: **Phase 0–3 đã triển khai**; Phase 4 (mở rộng, tuỳ chọn) chưa. Nhánh: `feature/qa-desk-module`. Bốn đề xuất ở mục 8 đã được chốt.

Đưa toàn bộ Fiza QA Desk (Phase 1–5 và Mạng yếu/API) vào AMC thành module **QA Desk · Kiểm thử**, rồi làm lại giao diện. Mục tiêu UX chính: cấu hình và chạy một lượt test **trên một màn hình**. Hiện tại người dùng phải đi qua ba tab (Workspace → Scenarios → Devices) và không thấy môi trường, thiết bị đang chọn ở chỗ bấm Chạy.

Tóm tắt:

- **Lõi giữ nguyên, UI viết lại.** Models, services và controller (khoảng 3.500 dòng, có 28 test) được port gần nguyên văn. Còn `workspace_screen.dart` (1.640 dòng, 68 màu đặt cứng cho nền sáng) thì viết lại theo token của AMC.
- **Sống theo app, không theo trang.** Một lượt integration test, Appium và proxy mạng yếu phải tiếp tục chạy khi người dùng quay về màn hình release.
- **Không mất dữ liệu cũ.** Dữ liệu cũ gồm 2 nguồn, 7 lượt và 44 suite run. Khi nhập, dữ liệu được sao chép (không di chuyển) sang `qa_desk/`, đồng thời sửa lại các đường dẫn tuyệt đối trong SQLite.
- **Sáu tab còn ba khu vực:** Chạy test · Kịch bản · Kết quả. Thiết bị và Mạng yếu chuyển thành bảng phụ, mở từ thanh cấu hình nằm cạnh nút Chạy.

## Tiến độ Phase 3

- **Lối vào (QAD-016):**
  - Panel Dự án có nhóm **Công cụ dự án** gồm Plan Studio và QA Desk; cả hai mở theo dự án đang chọn.
  - Menu ⋮ Tự động hoá có mục QA Desk.
  - Palette có `tool.qaDesk` và ba lệnh mới: **QA: chạy các suite đã chọn**, **QA: chạy lại suite lỗi của lượt gần nhất**, **QA: báo cáo issue của lượt gần nhất**. Các lệnh này mở QA Desk kèm một `QaDeskIntent`. Nếu chưa làm được thì báo rõ lý do: còn lỗi chặn ở preflight, chưa có lượt nào, lượt gần nhất không có suite lỗi, hoặc đang có lượt chạy.
- **Nguồn từ dự án AMC (QAD-017):**
  - Nút **Thêm nguồn…** liệt kê dự án đang mở và các dự án "Gần đây" chưa là nguồn, rồi mới đến "Chọn thư mục khác…".
  - Màn hình trống có sẵn nút thêm nhanh tối đa 4 dự án.
  - Mở QA Desk từ một dự án chưa là nguồn thì hiện gợi ý **Thêm dự án này**.
  - QA Desk biết về AMC qua interface `QaDeskHost`; bản cài phía AMC là `AmcQaDeskHost` (`lib/app/services/qa_desk_host_service.dart`), đăng ký trong `AppBinding`. Module không phụ thuộc vào `HomeController`.
- **Chạy nền và trùng dự án (QAD-018):**
  - Chip QA nằm ở đầu phải thanh tiến trình đáy của shell. Chip theo dõi lượt đang chạy, và giữ kết quả cho tới khi mở lại QA Desk (`QaDeskRuntime.seenBatch`); bấm vào để mở QA Desk.
  - Khi AMC đang release đúng dự án đang test, preflight hiện cảnh báo `projectBusy`, không chặn. So sánh đường dẫn qua `p.equals`, nên không phân biệt hoa thường trên Windows.
- **Khoá thiết bị (QAD-019):** `lib/app/modules/shared/device_run_lock.dart` thay cho khoá tĩnh trong `BundleCheckService` và hàng đợi riêng của controller QA. Trang Kiểm tra AAB, bot Telegram và suite mobile của QA giờ xếp chung một hàng; suite không cần thiết bị thì không phải chờ.
- **Tài liệu (QAD-020):** README của AMC có mục **QA Desk** (cách dùng, manifest mobile, nơi lưu dữ liệu, CLI, lệnh test module). README của `fiza_qa_desk` ghi rõ đã chuyển vào AMC và không dùng app cũ nữa.
- **Kiểm chứng:**
  - Analyze sạch. Toàn bộ suite có 740 qua, 1 bỏ qua, vẫn chỉ 1 lỗi có sẵn.
  - Thêm 15 test trong `test/qa_desk_integration_test.dart`:
    - khoá thiết bị theo cả hai chiều;
    - cảnh báo trùng dự án;
    - menu thêm nguồn, thư mục không phải dự án, gợi ý dự án, thêm nhanh khi trống;
    - cảnh báo khi release bắt đầu giữa chừng;
    - bốn intent của palette;
    - chip trên shell.
  - Thêm 1 test shell trong `options_panel_layout_test.dart` cho panel, menu và palette.
  - Lệnh test module ghi trong README chạy đúng (76 test).
  - `flutter build windows --release` thành công (`build\windows\x64\runner\Release\app_management_center.exe`).
- **Giới hạn đã biết:**
  - "Đang release" được suy ra từ `ReleaseRunnerService.isBusy` cộng với dự án đang mở, vì runner không lưu nó đang chạy ở thư mục nào. Lệnh từ điện thoại chạy ở thư mục khác thì không được nhận ra.
  - `AmcQaDeskHost` chưa có test riêng, vì cần dựng `HomeController`.
- **Chưa kiểm**, như các phase trước: bấm qua trong AMC thật, và đường thoát app qua runner Windows.

## Tiến độ Phase 2

UI cũ (`views/legacy/`) và trang tạm của Phase 1 đã xoá.

- **Khung trang** (`views/qa_desk_view.dart`): AppBar có chip trạng thái luôn hiện ("Đang chạy 3/7 · 1 lỗi", hoặc "Lượt vừa xong: 4/5 qua"; bấm để về Chạy test) và nút ⓘ mở bảng hướng dẫn. Bên dưới là ba khu vực **Chạy test · Kịch bản · Kết quả**; khu vực mở gần nhất được nhớ trong phiên. Lượt chạy xong khi đang ở khu vực khác thì báo bằng SnackBar có nút "Xem".
- **Chạy test** (`views/run_page.dart`, `widgets/suite_tree.dart`):
  - Một cây nguồn/suite có checkbox ba trạng thái, ô lọc theo tên, lệnh và tag, và môi trường chọn ngay trên dòng nguồn (kèm 🔑 *x/y*).
  - Thanh chip Thiết bị · Mạng · Appium.
  - Thanh hành động dính đáy: tóm tắt lựa chọn, liệt kê lý do bị chặn, mỗi lý do có nút sửa ngay ("Chọn thiết bị", "Nhập secret").
  - Danh sách lượt chạy và log được chia bằng thanh kéo. Log có lọc, copy, phóng to và nút xuống dòng mới nhất, và tự mở vào suite đang chạy hoặc suite lỗi đầu tiên.
  - Thẻ kết quả không chặn thao tác: Báo cáo issue, Chạy lại suite lỗi, Mở trong Kết quả.
  - Khi chưa có nguồn, trang hiện ba bước hướng dẫn. Cửa sổ hẹp hơn 1.050 px thì tách thành hai tab.
- **`preflight()`** trong controller chặn trước khi chạy các trường hợp: chưa chọn suite, suite cần thiết bị nhưng chưa có thiết bị, suite cần máy thật mà đang chọn máy ảo, thiếu Appium, thiếu secret, mạng đang bật/tắt. Mạng yếu đang bật chỉ hiện thành ghi chú, không chặn.
- **Kịch bản** (`views/scenarios_page.dart`, `views/scenario_editors.dart`): bên trái là danh sách nguồn và môi trường (● đánh dấu môi trường lượt tới sẽ dùng). Bên phải là test case, lọc theo module. Form soạn test case và môi trường mở dạng bảng bên phải. Chạy một test case sẽ chuyển sang Chạy test.
- **Kết quả** (`views/results_page.dart`): danh sách lượt bên trái. Header của lượt có Chạy lại suite lỗi, Báo cáo issue và Xuất (HTML/JUnit/JSON). Ba tab Chi tiết · So sánh · Xu hướng; So sánh mặc định với lượt liền trước.
- **Bảng phụ:** Thiết bị & Appium, Mạng yếu (cả API probe và hướng dẫn nối proxy). Hộp nhập secret chỉ ghi đè ô nào có nhập, nên không xoá mất secret đã nhập trước đó.
- **Theme:** `theme/qa_tokens.dart` suy ra mọi màu từ `AppPalette`; trong module không còn `Color(0x…)` nào. AMC chưa có theme cho `SegmentedButton` và chip, mà màu mặc định của Material làm chữ của mục đang chọn gần như chìm ở cả 3 theme. Vì vậy module dùng `qaSegmentedStyle` và `QaChoiceChip`.
- **Widget dùng chung:** `ModuleCard`, `SectionLabel`, `NoticeBox`, `StatusChip` chuyển từ `mail_cleaner_widgets.dart` sang `modules/shared/module_widgets.dart`. Mail Cleaner và Kiểm tra AAB đã đổi import, hành vi không đổi.
- **Việt hoá:** chuỗi trong controller và service theo bảng ở mục 5.7, gồm cả gợi ý trong báo cáo issue ("Bấm chip Thiết bị…" thay cho "Vào Devices"). Riêng dòng `Network simulation:` trong log vẫn giữ tiếng Anh, vì báo cáo issue đọc lại đúng tiền tố đó.
- **Hai bug test bắt được:**
  1. *Có từ app cũ:* suite nào lỗi cũng bị chụp màn hình điện thoại đang chọn, kể cả `flutter analyze` hay unit test, nên báo cáo issue kèm ảnh không liên quan và gọi `adb` thừa. Giờ chỉ chụp khi suite thực sự chạy trên thiết bị.
  2. *Ở trang mới:* trang Kết quả gọi `notifyListeners` giữa lúc build. Đã lùi việc nạp dữ liệu sang sau frame đầu.
- **Kiểm chứng:**
  - Analyze sạch. Toàn bộ suite có 724 qua, 1 bỏ qua, vẫn chỉ 1 lỗi có sẵn.
  - So với Phase 1: bỏ 3 widget test của UI cũ, thêm 14 widget test (`test/qa_desk_view_test.dart`) và 5 test controller (chụp màn hình có điều kiện, preflight, gộp secret). Fake dùng chung nằm ở `test/qa_desk_fakes.dart`.
  - Test chụp màn hình bật bằng `QA_DESK_SCREENSHOTS=<thư mục>`, chụp 21 ảnh: 3 khu vực, bảng Thiết bị, bảng Mạng yếu, form test case và tab Xu hướng, mỗi thứ ở 3 theme. Đã xem từng ảnh. Bốn lỗi hiển thị phát hiện qua ảnh đã sửa:
    - chữ của segment và chip đang chọn bị chìm;
    - bảng bên trong suốt ở theme Cyber;
    - bóng đổ của bảng bên thành dải đen cứng;
    - "0.5 KB/s" và "83.3%" viết theo kiểu dấu chấm thập phân.
- **Lệch so với thiết kế:**
  - Chip Thiết bị luôn hiện, chỉ mờ đi khi không suite nào cần thiết bị; nhờ vậy không phải chọn suite mobile trước mới vào được bảng Thiết bị.
  - Thẻ kết quả nằm dưới thanh chip, không thay chỗ thanh chip.
  - Hộp nhập secret vẫn là dialog, vì form ngắn.
- **Chưa kiểm:** vẫn chưa bấm qua trong AMC thật, cùng lý do ở Phase 1. Chưa thử điều hướng chỉ bằng bàn phím.

## Tiến độ Phase 0–1

Phase 1 tạm dùng nguyên màn hình của app cũ, bọc trong theme sáng của nó; Phase 2 đã thay.

- **Phase 0:** đã sao lưu dữ liệu cũ (49 file, 8,4 MB) vào `C:\Users\miste\Desktop\Work\Project\qa_desk_data_backup_20261001`. Thêm `yaml: ^3.1.4`; lockfile chỉ đổi mục này. Baseline AMC: analyze sạch, 663 qua, 1 bỏ qua, 1 lỗi có sẵn (`machine_power_service_test`).
- **Mã:** `lib/app/modules/qa_desk/` gồm `models/`, `services/`, `controllers/` port gần nguyên văn, và `views/legacy/` (UI cũ, sẽ xoá ở QAD-014). Mã port biên dịch được với language version 3.11, không phải sửa cú pháp; chỉ `dart format` đổi vài dòng.
- **Lưu trữ:** registry, history và artifact mặc định ghi vào `<AppSupport>/qa_desk/`. `QaDeskStorage.importLegacyIfNeeded()` chép vào `qa_desk.importing/`, sửa path (khớp tiền tố không phân biệt hoa thường, bỏ qua path nằm ngoài thư mục cũ, chịu được DB schema v1), rồi mới đổi tên.
- **Runtime:** `QaDeskRuntime` nằm ở `services/`, cạnh `PlanStudioRuntime`. Runtime mở lười và chỉ mở một lần, mở lỗi thì lần sau thử lại được. Khi thoát app, `AppLifecycleListener` gọi `controller.shutdown()` để dừng cây tiến trình của suite và Appium. Kết quả nhập dữ liệu được báo một lần trên trang.
- **Lượt bị ngắt:** `RunHistoryStore.recoverInterruptedBatches()` chạy khi khởi tạo. Batch còn ở trạng thái running được đóng lại: suite đã xong giữ kết quả, phần còn lại tính là đã dừng.
- **Kiểm chứng:** analyze sạch. Toàn bộ suite có 708 qua (thêm 45), 1 bỏ qua, vẫn chỉ 1 lỗi có sẵn. 45 test mới gồm 28 test port từ app cũ và 17 test mới: 8 cho bước nhập, 4 cho runtime (có test thoát app), 5 cho controller (chạy, dừng, shutdown, chạy lại suite lỗi, môi trường và secret).
- **Dữ liệu thật**, kiểm trong thư mục tạm, không đụng thư mục của AMC: nhập 49 file, sửa 47 path (44 log và 3 ảnh), thấy đủ 2 nguồn (8 và 3 suite), 7 lượt, 44 suite run; mọi log đều nằm trong thư mục mới và đọc được. Đã chạy thật suite Flutter Analyze của FizaHUB Flutter: qua sau 28 giây, log ghi đúng chỗ. Thư mục cũ vẫn đủ 49 file. Hai CLI `tool/qa_validate_*.dart` chạy đúng trên `fizahub_app` và `fizahub_miniapp`.
- **Chưa kiểm:**
  - Bấm qua trang trong AMC thật. Bản AMC đã cài đang chạy, và mở thêm bản dev sẽ giành lệnh relay điện thoại/Telegram với nó.
  - Đóng cửa sổ thật có đi qua `onExitRequested` hay không. Test chỉ xác nhận phía framework; phía runner Windows chưa thử.

## 1. Mục tiêu và phạm vi

Trong phạm vi:

1. Port mọi chức năng đang có: nguồn và manifest `.fiza-qa/project.yaml`, chạy song song theo nguồn và tuần tự theo suite, dừng cả cây tiến trình. Kèm theo: lịch sử SQLite, artifact, thiết bị và Appium, ảnh chụp khi lỗi, kịch bản và môi trường, secret trong phiên, báo cáo, so sánh, chạy lại suite lỗi, xuất HTML/JUnit/JSON, báo cáo issue, proxy mạng yếu và API probe.
2. Làm lại UI theo theme Console/Cyber/Default của AMC và Việt hoá đồng bộ với shell.
3. Nối với AMC: command palette, dự án gần đây, khoá thiết bị chung với Kiểm tra AAB.
4. Nhập dữ liệu từ app QA Desk cũ, chỉ chạy một lần.

Ngoài phạm vi bản đầu (xem Phase 4): chạy test từ điện thoại, gửi kết quả qua Telegram, đồng bộ team Firebase, tạo task Plan Studio tự động, gộp cơ chế dò thiết bị với Kiểm tra AAB.

## 2. Hiện trạng đã kiểm tra

| Thành phần | Fiza QA Desk | AMC | Hướng tích hợp |
|---|---|---|---|
| State | `QaWorkspaceController` (ChangeNotifier, 894 dòng) kèm `NetworkTestController` | Module dùng ChangeNotifier và mở bằng `Navigator.push`; shell dùng GetX | Giữ ChangeNotifier, nhưng do một runtime sống theo app nắm giữ (mục 4.2) |
| UI | 6 tab và 2 nút trong một `Wrap`; 68 `Color(0x…)` đặt cứng; chỉ có theme sáng | `AppPalette` với 3 theme; `StudioTokens` suy ra từ palette | Viết lại UI; thêm `QaTokens` suy ra từ palette |
| Lưu trữ | `%APPDATA%\vn.fizahub.qa\Fiza QA Desk\`: `sources.json`, `fiza_qa_desk.db` (schema v3), `artifacts/`, tổng 8,4 MB | `%APPDATA%\com.example\App Management Center\`, mỗi module một thư mục con (`plan_studio/`, `bundle_check/`) | Dùng thư mục `qa_desk/`; nhập dữ liệu cũ một lần, sao chép chứ không di chuyển |
| Đường dẫn trong DB | `suite_runs.log_path` và `screenshot_path` là đường dẫn tuyệt đối vào thư mục cũ | — | Khi nhập, `UPDATE … replace()` sang gốc mới |
| Chạy tiến trình | `SafeProcessRunner`: allowlist `flutter, dart, node, npm, npx, adb, appium`; `taskkill /T /F` | `ReleaseRunnerService` cho release | Giữ runner riêng của QA vì đây là ranh giới an toàn; không gộp |
| Thiết bị | `flutter devices --machine` (Android và iOS); hàng đợi `_deviceQueue` nằm trong controller | Kiểm tra AAB: adb và AVD, tự bật AVD; khoá `static _deviceLock` trong `BundleCheckService` | Bản đầu giữ cách dò của QA, nhưng dùng **một khoá thiết bị chung** cho cả app |
| Git | `GitMetadataService` (40 dòng) | `GitInspectorService` | Giữ của QA; gộp để sau |
| Dự án | Thêm "source" bằng cách chọn thư mục | Có dự án gần đây và dự án đang mở | Thêm nguồn bằng một click từ dự án của AMC |
| Dependency | `yaml`, `sqflite_common_ffi`, `file_selector`, `path_provider`, `path` | `yaml` mới chỉ là transitive, các gói còn lại đã có | Thêm `yaml: ^3.1.4` làm dependency trực tiếp |
| SDK | `^3.12.2` | `^3.11.4`; máy đang dùng Flutter 3.44.9 / Dart 3.12.2 | Mã port được biên dịch với language version 3.11 của AMC. `flutter analyze` ở QAD-004 sẽ bắt cú pháp chỉ có từ 3.12; sửa mã chứ không nâng constraint |
| Ngôn ngữ | Trộn Anh và Việt (Workspace, Sources, Live run, Re-run failed…) | Toàn bộ tiếng Việt (commit `c027837`) | Việt hoá theo bảng thuật ngữ ở mục 5.7 |
| Kiểm chứng | `flutter analyze` sạch, 28 test qua (10 file service, 3 file widget; chưa có test cho controller) | Mỗi module có lệnh test riêng trong README | Port nguyên test service, viết lại test widget |

## 3. Vấn đề UX của QA Desk hiện tại

Đây là lý do cần refactor, nên mỗi mục đều có cách xử lý tương ứng ở mục 5.

1. **Cấu hình một lượt chạy rải ở ba tab.** Suite chọn ở Workspace, môi trường ở Scenarios, thiết bị ở Devices. Nút "Chạy đã chọn" không cho biết đang dùng môi trường nào, thiết bị nào, nên rất dễ chạy nhầm staging với production.
2. **Mạng yếu tác động lên mọi suite nhưng không hiện ở nơi chạy.** Quên tắt giả lập thì lượt sau chậm hoặc lỗi mà không rõ vì sao.
3. **Lỗi chỉ hiện ra sau khi chạy.** Suite cần thiết bị mà chưa chọn thiết bị, hoặc secret chưa nhập, sẽ fail ngay khi chạy với lỗi kiểm tra, thay vì bị chặn trước khi bấm.
4. **Chọn nguồn và suite tách thành hai cột.** Phải tick nguồn ở cột trái thì suite mới hiện ở cột giữa, và không có trạng thái "chọn một phần".
5. **History và Reports tách hai tab dù cùng nói về các lượt cũ.** Muốn lấy báo cáo issue của một lượt cũ phải vào Reports, chọn After rồi bấm nút.
6. **Điều hướng phẳng.** 6 tab và 2 nút đứng ngang hàng; "Kết quả test" và "Hướng dẫn" trông giống tab.
7. **Popup kết quả tự bật dạng modal** khi chạy xong và chặn mọi thao tác.
8. **Danh sách lượt chạy cao cố định 156 px**, giành chỗ với log.
9. **Màu đặt cứng cho nền sáng** nên vỡ giao diện trong theme Console và Cyber.

## 4. Kiến trúc tích hợp

### 4.1 Vị trí mã

```
lib/app/modules/qa_desk/
  models/       qa_models, scenario_models, report_models            ← port nguyên
  services/     source_discovery, safe_process_runner, run_history_store,
                artifact_store, source_registry, scenario_catalog_store,
                report_analytics, report_export, issue_report,
                appium_server, mobile_device, device_discovery,
                git_metadata, weak_network_proxy                     ← port, gốc thư mục được inject
                qa_desk_storage.dart                                 ← mới: gốc qa_desk/ và nhập dữ liệu cũ
                qa_desk_runtime.dart                                 ← mới: singleton sống theo app, cạnh PlanStudioRuntime
                qa_desk_host.dart                                    ← mới: những gì QA Desk cần biết về AMC
  controllers/  qa_workspace_controller, network_test_controller     ← port, thêm preflight (mục 5.3)
  theme/        qa_tokens.dart                                       ← mới, theo mẫu StudioTokens
  models/       preflight.dart                                       ← mới: lý do chặn trước khi chạy
  views/        qa_desk_view.dart (khung + runtime), run_page.dart, scenarios_page.dart,
                scenario_editors.dart, results_page.dart, devices_sheet.dart,
                network_sheet.dart, secrets_dialog.dart, issue_report_dialog.dart,
                help_sheet.dart, qa_shell_status.dart (chip trên shell AMC)
  widgets/      suite_tree.dart, log_console.dart, qa_widgets.dart, add_source_button.dart
lib/app/modules/shared/module_widgets.dart                          ← ModuleCard, SectionLabel, NoticeBox, StatusChip
lib/app/modules/shared/device_run_lock.dart                         ← khoá thiết bị chung với Kiểm tra AAB
lib/app/services/qa_desk_host_service.dart                          ← AmcQaDeskHost, đăng ký trong AppBinding
tool/qa_validate_sources.dart, tool/qa_validate_catalogs.dart       ← port CLI
```

Không dùng path dependency trỏ tới `fiza_qa_desk` vì ba lý do: repo đó chưa có git, UI đằng nào cũng viết lại, và mọi module khác của AMC đều nằm trong `lib/app/modules`. Module là một thư viện riêng, không phải `part of home_view.dart`, nên không đụng tên với các widget private của shell. Sau khi tích hợp, `fiza_qa_desk` được đóng băng và README của nó trỏ sang AMC.

### 4.2 Vòng đời

Mail Cleaner và Kiểm tra AAB tạo controller theo trang. QA Desk không làm vậy được, vì đóng trang sẽ giết luôn lượt chạy đang dở, Appium và proxy.

- `QaDeskRuntime.open()` mở lười theo mẫu `PlanStudioRuntime.open()`: lần đầu vào module hoặc lần đầu gọi lệnh QA từ palette. Lúc đó mới mở SQLite, registry, catalog và kiểm tra Appium, nên AMC khởi động không chậm thêm.
- **Đóng trang không có nghĩa là dừng chạy.** Khi đang chạy, shell hiện một chip `QA 3/7 · 1 lỗi`; bấm vào để quay lại trang Chạy test.
- Khi AMC thoát thật (không phải thu xuống tray), `dispose()` dừng tiến trình bằng `taskkill /T`, rồi dừng Appium và proxy.
- Nếu một release đang chạy trên **cùng thư mục dự án** (`runner.isBusy` và trùng path), thanh hành động sẽ cảnh báo trước khi chạy. Lý do: `flutter test` và `flutter build` tranh nhau thư mục `build/` cùng file khoá của Gradle.

### 4.3 Lưu trữ và nhập dữ liệu cũ

- Gốc mới là `<AppSupport>/qa_desk/`, chứa `sources.json`, `qa_desk.db` và `artifacts/`. `FileSourceRegistry`, `SqliteRunHistoryStore` và `ArtifactStore` nhận gốc thư mục qua tham số thay vì tự gọi `getApplicationSupportDirectory()`. Cách này dễ test, và các file không còn rơi vào gốc chung của AMC.
- **Nhập một lần** khi runtime mở: nếu `qa_desk/` chưa có `qa_desk.db` mà `%APPDATA%\vn.fizahub.qa\Fiza QA Desk\` tồn tại, thực hiện theo thứ tự:
  1. Sao chép `sources.json`, `fiza_qa_desk.db` (thành `qa_desk.db`) và `artifacts/` vào thư mục tạm `qa_desk.importing/`.
  2. Trong bản sao, chạy `UPDATE suite_runs SET log_path = replace(log_path, <gốc cũ>, <gốc mới>), screenshot_path = replace(…)`.
  3. Đổi tên `qa_desk.importing/` thành `qa_desk/` và ghi `imported_from.txt`.

  Nếu thất bại thì xoá bản tạm, giữ nguyên dữ liệu cũ, module vẫn mở với workspace trống và báo lỗi. Thao tác này tuân theo nguyên tắc của `LegacyStorageMigrationService`: chỉ sao chép, không bao giờ di chuyển.
- `.fiza-qa/project.yaml` và `.fiza-qa/scenarios.json` nằm trong các repo được test. **Giữ nguyên tên thư mục `.fiza-qa`** để các repo đã có manifest vẫn chạy được.
- Secret trong phiên vẫn chỉ nằm trong bộ nhớ: không ghi vào catalog, log hay lịch sử. Hành vi bảo mật không đổi.
- Thư mục artifact chưa có cơ chế dọn. Bản đầu giữ nguyên như vậy; Phase 4 thêm giới hạn số lượt (Kiểm tra AAB đang giữ 20 bản mới nhất).

### 4.4 Điểm nối với AMC

| Điểm nối | Bản đầu | Về sau |
|---|---|---|
| Lối vào | Panel Dự án: nhóm **Công cụ dự án** gồm *Plan Studio* và *QA Desk*, cả hai mở theo dự án đang chọn. Menu ⋮ Tự động hoá. Palette: `tool.qaDesk` | — |
| Lệnh palette | `qa.run` (chạy lựa chọn đã lưu), `qa.rerunFailed` (chạy lại suite lỗi của lượt gần nhất), `qa.lastReport` | Lệnh chạy cho từng suite |
| Dự án AMC thành nguồn | Nút "Thêm nguồn" có danh sách dự án gần đây và dự án đang mở. Mở QA Desk từ một dự án chưa là nguồn thì hiện gợi ý "Thêm dự án này" | — |
| Khoá thiết bị | Tách `_deviceLock` khỏi `BundleCheckService` thành `DeviceRunLock` dùng chung. Suite mobile của QA, Chạy thử AAB và bot Telegram xếp chung một hàng | Khoá theo từng thiết bị |
| Báo cáo issue | Copy task, Copy báo cáo (như cũ) | Nút "Tạo task trong Plan Studio" dùng `ensureProject(path)` và `save()` |
| Telegram, điện thoại, API Tool | — | Xem Phase 4 |

## 5. Thiết kế UI mới

### 5.1 Nguyên tắc

1. **Một màn hình cho một lượt chạy.** Mọi thứ ảnh hưởng tới lượt chạy (môi trường, thiết bị, mạng, Appium) luôn hiện cạnh nút Chạy.
2. **Chặn lỗi trước khi chạy:** thiếu thiết bị, thiếu secret, suite cần máy thật mà đang chọn máy ảo, hoặc release đang chạy trên cùng dự án.
3. **Ba khu vực thay cho sáu tab.** Thiết bị và Mạng yếu là bảng phụ, mở từ chip của chính nó.
4. **Kết quả hiện tại chỗ.** Chỉ mở modal khi người dùng chủ động bấm.
5. **Màu lấy từ palette.** Trạng thái dùng `success/danger/info/warning/idle`, không có màu đặt cứng.
6. **Toàn bộ tiếng Việt.** Giữ nguyên các tên kỹ thuật như suite, Appium, proxy, JUnit.

### 5.2 Khung trang

Trang mở toàn màn hình bằng `showQaDesk(context, {projectPath})`, giống Kiểm tra AAB.

```
┌ ← QA Desk · Kiểm thử    [ Chạy test | Kịch bản | Kết quả ]        ● Đang chạy 3/7 · 1 lỗi   ⓘ ┐
```

- Ba khu vực nằm trong một `SegmentedButton` trên AppBar. Khu vực đang mở được nhớ lại giữa các lần vào.
- Chip trạng thái bên phải luôn hiển thị ở mọi khu vực; bấm vào để về Chạy test.
- Nút ⓘ mở bảng hướng dẫn ngắn (thay dialog Hướng dẫn hiện tại). Phần hướng dẫn chính chuyển vào các trạng thái trống.

### 5.3 Chạy test

```
┌─ Nguồn & suite ─────────────────────────┬─ Lượt chạy ───────────────────────────────────────┐
│ [🔍 Lọc theo tên, tag]   [+ Thêm nguồn ▾] │ [📱 Pixel 7 · máy ảo ▾] [📶 Mạng: bình thường ▾]   │
│                                          │ [Appium: tắt]                                      │
│ ▾ ◩ FizaHUB Flutter   Flutter · manifest │───────────────────────────────────────────────────│
│     Môi trường [staging ▾]  🔑 2/2   ⋮   │ ✔ FizaHUB Flutter · Analyze                  12 s │
│     ☑ Flutter Analyze      static smoke  │ ⟳ FizaHUB Flutter · Unit tests               41 s │
│     ☑ Unit tests                         │ ◌ Mini App · Build                           chờ  │
│     ☐ Android smoke        📱 thiết bị   │ ═══════════════ (kéo để chia) ═══════════════════ │
│ ▸ ☐ FizaHUB Mini App   Node · 0/3        │ Log · Unit tests            [Tìm] [Copy] [⤢] [⇣] │
│                                          │ > flutter test                                     │
│                                          │ 00:12 +45: …                                       │
├──────────────────────────────────────────┴───────────────────────────────────────────────────┤
│ 1 nguồn · 2 suite · staging · mạng bình thường                    [■ Dừng]  [▶ Chạy 2 suite] │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

- **Cây nguồn và suite** thay cho hai cột Sources và Test suites. Checkbox của nguồn có ba trạng thái (tất cả, một phần, không), nhánh mở/thu được, kèm số `x/y`. Ô lọc tìm theo tên suite và tag.
- **Môi trường chọn ngay trên dòng nguồn.** Biểu tượng 🔑 cho biết đã nhập đủ secret trong phiên hay còn thiếu; bấm vào để nhập. Phần định nghĩa môi trường vẫn ở Kịch bản.
- **Thanh cấu hình** gồm các chip:
  - *Thiết bị:* chỉ hiện khi có suite cần thiết bị. Chip đỏ nếu suite cần máy thật mà đang chọn máy ảo. Bấm để mở bảng Thiết bị.
  - *Mạng:* màu vàng khi đang bật giả lập. Bấm để mở bảng Mạng yếu.
  - *Appium:* chỉ hiện khi có suite cần Appium.
- **Thanh hành động dính ở đáy** tóm tắt lựa chọn và ghi rõ lý do chặn khi có. Nút Chạy hiển thị số suite. Controller có thêm `preflight()` trả về danh sách vấn đề chặn; logic lấy từ `MobileDeviceService.validateSuite` hiện có.
- **Danh sách lượt chạy và log** chia bằng splitter kéo được (dùng lại `_PanelSplitter`/MainPanel của AMC). Log có tìm kiếm, Copy, phóng to và nút bật/tắt tự cuộn.
- **Khi chạy xong**, thẻ kết quả thay chỗ thanh cấu hình: `5 suite · 4 qua · 1 lỗi · 2 phút 13 giây`, kèm các nút **Báo cáo issue**, **Chạy lại suite lỗi**, **Mở trong Kết quả**. Thẻ không chặn thao tác, và đóng khi bắt đầu chỉnh lựa chọn.
- **Trạng thái trống** là ba bước kèm nút (Thêm nguồn → Chọn suite → Chạy), có lối "Thêm từ dự án AMC".
- **Cửa sổ hẹp** (< 1050 px): hai cột chuyển thành tab *Chọn* | *Lượt chạy*, thanh hành động vẫn dính đáy.

### 5.4 Kịch bản

```
┌─ Nguồn ─────────────┬─ Test case · FizaHUB Flutter ──────── [Module: Tất cả ▾] [+ Test case] ⋮ ┐
│ ● FizaHUB Flutter   │ ▸ Đăng nhập OTP           auth · Unit tests               [▶]           │
│ ○ FizaHUB Mini App  │ ▾ Thanh toán thẻ          payment · Android smoke         [▶]           │
│─ Môi trường ────────│     Điều kiện · Các bước · Kết quả mong đợi                             │
│ staging   🔑 2  ⋮   │                                                                         │
│ prod      🔑 0  ⋮   │                      ┌─ Sửa test case (bảng bên) ───────────┐           │
│ [+ Môi trường]      │                      │ Tên * · Module · Suite liên kết *     │           │
└─────────────────────┴──────────────────────┴───────────────────────────────────────┴───────────┘
```

- Nguồn chọn bằng danh sách thay vì dropdown. Môi trường của nguồn được quản lý ngay bên dưới danh sách đó.
- Form test case và môi trường mở ở **bảng bên** thay vì AlertDialog dài, để vẫn nhìn được danh sách khi sửa.
- Dropdown "Suite liên kết" hiện kèm lệnh sẽ chạy.
- Import/Export catalog chuyển vào menu ⋮.

### 5.5 Kết quả (gộp History và Reports)

```
┌─ Các lượt ────────────┬─ 01/10 14:32 · 5 suite · 1 lỗi   [Chạy lại suite lỗi] [Báo cáo issue] [Xuất ▾] ┐
│ ● 01/10 14:32   4/5   │ [ Chi tiết | So sánh | Xu hướng ]                                           │
│ ● 01/10 11:05   5/5   │ Chi tiết: suite · trạng thái · thời gian · git · thiết bị · môi trường      │
│ ● 30/09 17:40   3/5   │   → chọn một suite: log, stack trace, ảnh chụp lỗi (debug viewer hiện có)   │
└───────────────────────┴─────────────────────────────────────────────────────────────────────────────┘
```

- Hành động cho một lượt (báo cáo issue, chạy lại suite lỗi, xuất file) nằm trên header của chính lượt đó, chỉ cần một click.
- **So sánh:** lượt đang xem là "sau"; người dùng chỉ chọn lượt "trước" (mặc định là lượt liền trước). Hai dropdown Before/After bị bỏ.
- **Xu hướng:** các chỉ số tỷ lệ qua, thời gian, suite chập chờn và suite chậm nhất, cùng biểu đồ tỷ lệ qua theo lượt.

### 5.6 Bảng phụ

- **Thiết bị:** danh sách thiết bị, nút quét lại, chọn thiết bị; nhãn cho máy ảo/máy thật và Android/iOS. Bên dưới là Appium (bật/tắt, cổng, 500 dòng log).
- **Mạng yếu:** chọn preset, bật/tắt, copy proxy URL, đếm kết nối, API probe và Copy báo cáo API (giữ nguyên chức năng). Phần hướng dẫn nối proxy cho Dart, Playwright và `adb reverse` đặt trong mục thu gọn được.

### 5.7 Bảng thuật ngữ

| Cũ | Mới |
|---|---|
| Fiza QA Desk | QA Desk · Kiểm thử |
| Workspace | Chạy test |
| Sources · Thêm source | Nguồn · Thêm nguồn |
| Test suites | Suite |
| Live run | Lượt chạy |
| Chạy đã chọn | Chạy *N* suite |
| Scenarios · Scenario catalog | Kịch bản |
| Linked suite | Suite liên kết |
| Preconditions · Steps · Expected result | Điều kiện · Các bước · Kết quả mong đợi |
| Environment · Session secrets | Môi trường · Secret trong phiên |
| History + Reports | Kết quả |
| Re-run failed | Chạy lại suite lỗi |
| Before / After | Lượt trước / Lượt đang xem |
| Devices | Thiết bị |
| Mạng yếu / API | Mạng yếu |
| passed · failed · stopped | qua · lỗi · đã dừng |

### 5.8 Token và widget dùng chung

- `QaTokens.of(context)` lấy từ `AppCyberTheme.activePalette` giống `StudioTokens`: màu theo trạng thái, nền console log, viền, bo góc, chữ số tabular. Không còn `Color(0x…)` nào trong module.
- `ModuleCard`, `SectionLabel`, `NoticeBox` và `StatusChip` đang nằm trong `mail_cleaner_widgets.dart`, và Kiểm tra AAB đã import chéo từ đó. QA Desk sẽ là module thứ ba dùng chúng, nên chuyển sang `lib/app/modules/shared/module_widgets.dart` trong một commit riêng, không đổi hành vi.

## 6. Lộ trình

Ước lượng tính theo ngày làm việc của một người. Mỗi phase kết thúc ở trạng thái chạy được và test xanh.

### Phase 0: Chuẩn bị (0,5 ngày)

- **QAD-001** Ghi baseline: `flutter analyze` và `flutter test` của cả hai repo. QA Desk đã kiểm: sạch, 28 test qua.
- **QAD-002** Sao lưu `%APPDATA%\vn.fizahub.qa\Fiza QA Desk\` ra ngoài trước khi thử nhập.
- **QAD-003** Thêm `yaml: ^3.1.4` vào `pubspec.yaml`, chạy `flutter pub get`.

### Phase 1: Port lõi, giữ UI cũ làm mốc (2 ngày)

- **QAD-004** Chép models, services và controller vào `lib/app/modules/qa_desk/`; inject gốc thư mục `qa_desk/` vào registry, history và artifact.
- **QAD-005** `QaDeskRuntime`: mở lười, giữ một controller cho cả app, dispose khi thoát.
- **QAD-006** `QaDeskStorage.importLegacyIfNeeded()`: sao chép vào thư mục tạm, sửa path trong DB rồi đổi tên. Test với thư mục giả: thành công, thiếu file, DB hỏng, đã nhập trước đó.
- **QAD-007** Port 10 file test service thành `test/qa_desk_*_test.dart`, viết thêm test cho controller (chạy, dừng, chạy lại suite lỗi, chọn môi trường) vì bản gốc chưa có; port hai CLI validate.
- **QAD-008** Mốc kiểm tra: gắn tạm `WorkspaceScreen` cũ (bọc trong `Theme` sáng) sau lệnh palette `tool.qaDesk`, để xác nhận đủ chức năng trên dữ liệu thật trước khi đổi UI.

**Điều kiện xong:** test port qua hết. Trong AMC thấy đủ 2 nguồn, 7 lượt cũ, mở được log cũ theo path mới. Chạy được suite Analyze của FizaHUB Flutter.

### Phase 2: UI mới (4 ngày)

- **QAD-009** Khung trang, `QaTokens`, ba khu vực, chip trạng thái; chuyển widget dùng chung sang `modules/shared`.
- **QAD-010** Chạy test: cây nguồn/suite, chọn môi trường trên dòng nguồn, thanh cấu hình, `preflight()`, thanh hành động, splitter giữa lượt chạy và log, thẻ kết quả, trạng thái trống, bố cục hẹp.
- **QAD-011** Bảng phụ Thiết bị/Appium và Mạng yếu/API probe.
- **QAD-012** Kịch bản: danh sách nguồn và môi trường, danh sách test case, bảng bên để sửa, nhập secret.
- **QAD-013** Kết quả: danh sách lượt; header hành động; ba tab Chi tiết, So sánh, Xu hướng; debug viewer.
- **QAD-014** Việt hoá theo mục 5.7; xoá UI cũ và mốc của QAD-008.
- **QAD-015** Widget test: cây chọn ba trạng thái, preflight chặn chạy, thẻ kết quả, so sánh mặc định lượt liền trước, chạy lại suite lỗi. Chụp màn hình cả ba theme qua biến môi trường `QA_DESK_SCREENSHOTS`, giống `STUDIO_SCREENSHOTS`.

**Điều kiện xong:** không còn `Color(0x` trong module. Ảnh chụp ba theme đọc rõ. Mọi luồng trong mục 3 có test hoặc có ảnh minh chứng.

### Phase 3: Nối vào AMC (1,5 ngày)

- **QAD-016** Lối vào: nhóm Công cụ dự án ở panel Dự án, menu ⋮ Tự động hoá, các lệnh palette ở mục 4.4.
- **QAD-017** Thêm nguồn từ dự án AMC; gợi ý khi mở QA Desk theo một dự án chưa là nguồn.
- **QAD-018** Chip trạng thái QA trên shell khi đang chạy nền; cảnh báo khi trùng dự án đang release.
- **QAD-019** Tách `DeviceRunLock` dùng chung với Kiểm tra AAB và bot Telegram; test hai bên xếp hàng đúng thứ tự.
- **QAD-020** Thêm mục **QA Desk** vào README (cách dùng, vị trí dữ liệu, lệnh test module); README của `fiza_qa_desk` trỏ sang AMC.

**Điều kiện xong:** toàn bộ suite AMC qua (trừ `test/machine_power_service_test.dart` đã hỏng từ trước). Build Windows release chạy được. Đóng trang trong lúc đang chạy thì lượt chạy vẫn tiếp tục và chip trên shell đưa về đúng chỗ.

### Phase 4: Mở rộng (tuỳ chọn, làm sau khi đã dùng thật)

Tài khoản demo và kịch bản tự thao tác trên app (Maestro, kho tài khoản của team) có plan riêng: [qa-desk-demo-account-plan.md](qa-desk-demo-account-plan.md).

- **QAD-021** Báo cáo issue tạo task Plan Studio (liên kết task với lượt chạy).
- **QAD-022** Gửi tóm tắt lượt chạy vào nhóm Telegram release.
- **QAD-023** Scope `qa` cho điện thoại: chạy lựa chọn đã lưu và xem kết quả.
- **QAD-024** Gộp cách dò thiết bị với Kiểm tra AAB: dùng adb kèm AVD, bật được AVD đang tắt.
- **QAD-025** API Tool có tuỳ chọn gửi request qua proxy mạng yếu.
- **QAD-026** Giới hạn số lượt lưu artifact, kèm nút dọn.

## 7. Rủi ro

| Rủi ro | Cách xử lý |
|---|---|
| Nhập dữ liệu hỏng giữa chừng | Làm trong thư mục tạm rồi mới đổi tên; nguồn cũ không bị động tới; có bản sao lưu từ QAD-002 |
| Vẫn mở app QA Desk cũ sau khi đã nhập | Từ đó hai app ghi vào hai nơi khác nhau. README và màn hình sau khi nhập nói rõ là ngưng dùng app cũ |
| Tiến trình mồ côi khi AMC bị kill | Giữ `taskkill /T /F` khi dừng. Lúc mở runtime, ghi nhận các lượt đang ở trạng thái `running` trong DB thành `cancelled` |
| QA và release tranh thư mục `build/` | Cảnh báo ở thanh hành động khi trùng dự án (QAD-018) |
| QA và Kiểm tra AAB cùng cài lên một máy ảo | Dùng khoá thiết bị chung (QAD-019) |
| Đổi UI làm mất chức năng ít dùng | Mốc QAD-008 và bảng đối chiếu chức năng ở mục 1 dùng làm checklist khi nghiệm thu Phase 2 |
| Popup kết quả không còn tự bật | Thẻ kết quả tại chỗ vẫn tự hiện. Nếu thực tế cần popup thì thêm lại tuỳ chọn |

## 8. Cần chốt trước khi làm

1. **Tên module:** đề xuất "QA Desk · Kiểm thử", cùng kiểu với "Plan Studio · Công việc".
2. **Thay popup modal tự bật bằng thẻ kết quả tại chỗ:** đề xuất đồng ý (mục 3.7).
3. **Phạm vi refactor UI:** bản này chỉ làm lại UI của module QA, và gom lối vào Plan Studio cùng QA Desk vào nhóm Công cụ dự án. Việc sắp lại toàn bộ shell AMC (menu ⋮ đang chứa 5 công cụ) nên là một plan riêng.
4. **Ngưng app `fiza_qa_desk`** sau Phase 3.
