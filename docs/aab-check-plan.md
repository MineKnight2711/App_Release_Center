# Kế hoạch kiểm tra AAB: build đúng · đủ env · chạy được

Ngày: 2026-09-29, cập nhật 2026-09-30. Trạng thái: **Phase 1, 2 và 3 đã triển khai**, Phase 4 chưa. Nhánh: `feature/flowfin-module-rebrand`.

Một module mới trong AMC nhận file `.aab` (và `.apk`), giải nén, soi, cài thử, rồi trả một báo cáo ba nhóm: **Build**, **Env**, **Chạy**. File đến từ hai nguồn: kéo-thả vào AMC, hoặc bot Telegram tải về. Mọi thứ chạy trên máy Windows — Cloudflare Worker không chạy được `bundletool` hay `adb`, nên relay không tham gia.

## Tiến độ Phase 3

Chọn đường A ở mục 5.2: **local Bot API server**. Mở từ trang Kiểm tra AAB → **Bot Telegram**.

### Bot làm gì trong nhóm

1. Ai đó gửi file `.aab` vào nhóm → bot ghi file đó vào danh sách của nhóm (không trả lời gì).
2. Gõ `/aab` → bot gửi danh sách tối đa 8 file mới nhất, mỗi file một nút (tên, dung lượng, ngày).
3. Bấm một nút → bot nói ngay **"I'm downloading and checking the aab"** kèm tên file, *rồi* mới tải. Câu này sửa được trong cài đặt.
4. Tải xong → kiểm tĩnh (Build + Env) → nếu bật, chạy thử trên máy ảo → trả lời ngay dưới tin nhắn chứa file: kết luận, đếm lỗi/cảnh báo theo nhóm, tối đa 10 mục cần xem, cold start, và ảnh màn hình lúc kết thúc.

Cách khác: `/check` reply vào tin có file để kiểm ngay; gửi file thẳng cho bot trong chat riêng; `/status` xem bot đang làm gì. Hai người bấm cùng file → "đang được kiểm rồi"; file khác → "Đang xếp hàng (#n)".

**Giới hạn của Telegram, không phải của AMC:** bot chỉ thấy file gửi *sau* khi nó ở trong nhóm, và chỉ khi privacy mode tắt (BotFather → `/setprivacy` → Disable, rồi mời lại bot) hoặc bot là admin. Không có API nào cho bot đọc lịch sử nhóm. File cũ hơn: reply `/check` vào nó.

### Server

- **Build native trên máy này** bằng Visual Studio 2022 theo hướng dẫn chính thức của tdlib: `C:\Users\miste\Tools\telegram-bot-api\telegram-bot-api\bin\telegram-bot-api.exe`. Để ngoài AppData có chủ ý: tiến trình chạy từ ứng dụng đóng gói MSIX (như Claude desktop) ghi vào AppData sẽ bị ảo hoá vào thư mục riêng của gói — lần build đầu rơi đúng vào bẫy đó.
- **AMC tự khởi động server** khi cần: `--local`, `--http-ip-address=127.0.0.1` (ai tới được cổng là dùng được bot), thư mục làm việc `<bundle_check>/telegram/server`, log ở `server.log`. api_id/api_hash lưu trong Windows secure storage và chỉ đi qua biến môi trường `TELEGRAM_API_ID`/`TELEGRAM_API_HASH`, không nằm trên dòng lệnh. Server được để chạy khi AMC tắt, để thông báo release của phiên sau vẫn có chỗ đi.
- **Địa chỉ Bot API giờ cấu hình được** (`TelegramReleaseSettings.apiBaseUrl`), dùng chung cho thông báo release và bot kiểm AAB. Lưu cài đặt Telegram ở Options không còn xoá nó.
- **Chuyển bot** bằng nút "Chuyển bot sang server local": khởi động server → `logOut` ở cloud → `getMe` ở local → lưu địa chỉ. Có hộp xác nhận nói rõ: từ đó mọi thứ dùng bot phải qua server local, và Telegram không cho quay lại cloud trong 10 phút. Có nút ngược lại.
- Server trong container: khai ánh xạ đường dẫn phía server → thư mục trên máy (ở `--local`, `getFile` trả đường dẫn tuyệt đối trên đĩa của server, không phục vụ file qua HTTP).

### An toàn

- Chỉ trả lời trong chat được phép (mặc định: nhóm release đã khai ở Options) và, nếu khai, chỉ người được phép. Chat riêng chỉ mở cho user có tên trong danh sách. Nút bấm cũng kiểm quyền.
- Chạy thử từ Telegram **chỉ trên máy ảo**, không bao giờ cài lên máy thật.
- Tin trả lời không mang giá trị env, không mang log ngoài một dòng lỗi; token bị che trong mọi thông báo lỗi.
- Một khoá chung cho việc chạy thiết bị: trang AMC và bot không cài lên cùng máy ảo một lúc.

### Kiểm chứng

- 11 test cho bot với Bot API giả (thứ tự "nói trước rồi mới tải", nút chọn, quyền, 20 MB trên cloud, trùng/xếp hàng, offset, chuyển server, cờ khởi động server, định dạng tin) + 1 widget test cho hộp cài đặt. Toàn bộ suite: 631 qua.
- **Một lỗi do test bắt được:** khi `getUpdates` trả rỗng ngay lập tức, vòng poll chỉ chạy microtask và chặn cả event loop. Server thật giữ request 20 giây nên không lộ ra, nhưng một server trả lời vội sẽ làm AMC treo. Giờ poll rỗng quá nhanh thì nghỉ 1 giây.
- **Một lỗi ở chính test:** widget test bật bot đã khởi động vòng poll với HTTP client thật, gọi `api.telegram.org` bằng token giả. Đã tiêm client giả ném lỗi khi bị gọi, để không test nào ra mạng được nữa.
- **Server thật:** build xong Bot API 10.3 (`telegram-bot-api.exe`, 27,8 MB). `LocalBotServer` của AMC khởi động nó với credential giả trên cổng thử 18081: chỉ nghe `127.0.0.1` (không mở `0.0.0.0`), trả 404 ở `/`, gọi lần hai không bật thêm bản nữa. Đã tắt server thử sau đó; bot của bạn không bị đụng tới.
- **Chưa chạy với Telegram thật:** cần bạn lấy api_id/api_hash ở my.telegram.org và bấm "Chuyển bot sang server local" — việc `logOut` bot khỏi cloud là của bạn quyết.

### Lệch so với plan

- **Không có `/cancel`**: bộ kiểm chưa dừng được giữa chừng.
- **Không tự kiểm mỗi file mới**: theo yêu cầu, bot cho chọn từ danh sách thay vì tự kiểm mọi file gửi lên.
- **Không tải qua link Google Drive**: với local server không còn cần đường vòng này.
- **Giới hạn gửi APK 50 MB của thông báo release chưa nâng**, dù local server nhận tới 2000 MB — để việc riêng.

## Tiến độ Phase 2

Thẻ **Chạy được không** trong báo cáo có chọn thiết bị, số giây theo dõi (10/20/30/60) và nút **Chạy thử**. Lựa chọn được nhớ giữa các phiên.

- **AAB-007 xong.** Danh sách thiết bị = `adb devices` (kèm model, Android, ABI, tên AVD qua `emu avd name`) cộng các AVD đang tắt từ `emulator -list-avds`. Chọn AVD đang tắt thì AMC bật nó (`-no-snapshot-save`, mỗi lần chạy bắt đầu từ cùng một trạng thái) và chờ `sys.boot_completed` tối đa 3 phút. **Mặc định luôn chọn máy ảo**; máy thật chỉ khi người dùng chọn.
- **AAB-008 xong.** R01 kiểm ABI và minSdk trước khi tốn công build. R02 `bundletool build-apks --connected-device`, ký bằng keystore của project (mật khẩu qua file tạm, xoá ngay). R03 cài bằng `install-apks`; trên máy ảo gỡ bản cũ trước để cài sạch, và tự gỡ-cài lại khi gặp `UPDATE_INCOMPATIBLE`/`VERSION_DOWNGRADE`; trên máy thật thì dừng và hỏi. R04 `am start -W`, lấy cold start. R05 theo dõi `pidof` từng giây, rồi đọc `logcat -b crash` và `main,system`: FATAL EXCEPTION đúng package, crash native, ANR, và lỗi Flutter/R8 **kèm tối đa 6 dòng stack**.
- **AAB-009 xong.** Chụp màn hình lúc 3 giây và lúc kết thúc; ảnh cuối gần như một màu (≥ 97%) → cảnh báo kẹt splash/màn trắng. Bộ giải PNG viết bằng Dart thuần (~100 dòng), không cần plugin. Ảnh và `logcat.txt` nằm trong thư mục job, báo cáo lưu lại lần chạy.
- **Kiểm chứng:** 13 test mới cho bộ chạy thiết bị với adb/bundletool giả có kịch bản (đường suôn sẻ, crash, màn hình trống, xung đột chữ ký máy thật/máy ảo, sai ABI, bật AVD), đọc log, giải PNG; thêm 1 widget test cho thẻ. Widget test không còn gọi adb thật của máy. Toàn bộ suite: 619 qua; vẫn chỉ `test/machine_power_service_test.dart` hỏng sẵn.

### Chạy thật trên ZFold_3 (Android 16, x86_64)

bundletool 1.18.3 tải qua chính `BundletoolManager` (khớp SHA-256), nằm ở `%APPDATA%\com.example\App Management Center\bundle_check\tools`. Fizahub 2.0.5, ký bằng keystore trong `android/env.properties`:

| Bước | Kết quả |
|---|---|
| Kiểm tĩnh + `bundletool validate` | 2,7 giây, OK |
| build-apks cho thiết bị | ~3 giây |
| Cài | ~6 giây |
| Cold start | 1,6 giây |
| 20 giây theo dõi | **Cảnh báo**: lỗi Flutter không bắt |
| Màn hình | Màn đăng nhập hiện đúng |

Lỗi bắt được: `Null check operator used on a null value` tại `Navigator.of` ← `showDialog` ← `UpgradeAlertState.showTheDialog` (package `upgrader`). `UpgradeAlert` ở bản 2.0.5 nằm ngoài Navigator nên hộp thoại "có bản mới" không bao giờ hiện. Code hiện tại (`AppUpgradeAlert` bọc từng route) có vẻ đã sửa — chưa build lại để xác nhận.

### Sự cố trong lúc kiểm chứng

Lượt chạy thứ hai, script thử của tôi chọn "thiết bị sẵn sàng đầu tiên" đúng lúc điện thoại SM-A556E được cắm vào, nên nhắm nhầm sang máy thật. Cài bị từ chối (`INSTALL_FAILED_UPDATE_INCOMPATIBLE` — máy có Fizahub ký bằng key khác) và chốt an toàn làm đúng: không gỡ, đánh dấu cần xác nhận. Trên máy đó chỉ có màn hình bị đánh thức; Fizahub vẫn còn nguyên. Sau đó controller được sửa để mặc định ưu tiên máy ảo, và lượt chạy lại được ghim vào `emulator-5554`.

### Lệch so với plan

- **Không có R07 riêng.** Dọn dẹp (force-stop, gỡ nếu bật "Gỡ app sau khi kiểm") chạy cuối mỗi lượt, không thành một dòng kết quả.
- **"Gỡ app sau khi kiểm" mặc định tắt**, để app còn trên máy ảo cho bạn bấm thử tay. Lượt sau vẫn cài sạch vì bản cũ được gỡ trước khi cài.
- **Log không stream**: xoá logcat trước khi mở app, đọc một lần sau khi theo dõi xong. Đơn giản hơn và đủ, vì chỉ cần log của đúng khoảng thời gian đó.



Module nằm ở `lib/app/modules/bundle_check/`, mở từ command palette ("Kiểm tra AAB") hoặc menu tràn của flow panel.

- **Đọc AAB bằng Dart thuần, không cần Java.** Manifest và `resources.pb` trong AAB là protobuf của aapt2, không phải binary XML, nên một bộ đọc protobuf ~150 dòng là đủ. Zip đọc bằng `RawZLibFilter` của `dart:io` với trần byte cho mỗi lần đọc (chống zip bomb); tên entry chỉ là khoá tra cứu, không bao giờ thành đường dẫn (chống zip-slip). Chữ ký đọc thẳng từ khối PKCS#7 trong `META-INF/*.RSA|EC`. Một AAB 170 MB mất **~2 giây**, chạy trên isolate riêng.
- **Kiểm chứng trên AAB thật trong `Desktop/Work/Release`**: fingerprint khớp `keytool -printcert`, căn trang ELF khớp script Python độc lập. Test dùng khối chữ ký thật tạo bằng keystore và `jarsigner` dùng một lần, không dùng dữ liệu bịa.
- **B01–B13 xong.** Ngưỡng targetSdk lấy theo mốc Play (36 từ 31/08/2026, có gia hạn tới 01/11/2026), để dạng bảng dữ liệu.
- **E00–E06 xong.** Contract env tự suy ra từ project: key mà code đọc (phân biệt `dotenv.get` / `env[...]!` là bắt buộc với `env[...]` / `maybeGet` / `fallback:` là tuỳ chọn), `.env.example`, **tên key** trong `.env` của project (không đọc giá trị), Firebase project từ `firebase_options.dart` và `google-services.json` theo flavor. Contract chỉnh tay được và lưu theo package.
- **Kiểm chứng:** 56 test mới (parser, B/E, scanner, pipeline đầu-cuối, widget), cộng một test chạy trên AAB thật khi đặt `AAB_CHECK_FIXTURE`. Toàn bộ suite: 605 qua. Lỗi duy nhất là `test/machine_power_service_test.dart` không load được — file chưa commit này đã hỏng cú pháp từ trước, không liên quan module này.

### Lệch so với plan

- **Chưa nhận `.apk`.** Manifest của APK là binary XML (AXML), cần một parser riêng. Để sau.
- **B11 là ước tính, không dùng `bundletool get-size`.** `get-size` cần build APK set trước, mất vài chục giây cho một AAB lớn. Thay bằng tổng dung lượng nén của phần arm64, so với lần kiểm trước cùng package.
- **Không đưa bundletool vào doctor.** Doctor tìm lệnh trên PATH, còn bundletool là jar AMC tự quản. Trạng thái và nút tải nằm ngay trên thanh tiêu đề của module. Jar được ghim bản 1.18.3 và kiểm SHA-256 trước khi dùng.
- **E01 đọc cả tên key trong `.env` của project.** Hầu hết project không có `.env.example`, và nhiều project đọc env qua hàm bọc (`dotenv.maybeGet(key)`), nên quét code không ra tên key. Key có trong `.env` hiện tại mà bundle thiếu → cảnh báo "bundle có thể build từ .env cũ".
- **E02 bắt cả chuỗi cấm trong libapp.so**, không chỉ trong `.env`: thấy host staging trong code đã compile là bằng chứng cụ thể nên để mức lỗi.

### Phát hiện khi chạy trên AAB thật

- **vMed Pro 1.5.0 và 1.5.1 (bản production) mang Firebase project `emed-dev-f0fe5`.** Chuỗi này nằm trong `libapp.so`, lấy từ `lib/firebase_options.dart`; còn `google-services.json` của flavor production là `emed-pro-29666` nhưng không được dùng (bundle không có resource `google_app_id`). Nếu không cố ý thì push và analytics của bản production đang đi vào project dev.
- **gcheck 1.0.6+20** (file tháng 9/2025): targetSdk 35 — Play không còn nhận bản cập nhật như vậy; và 4 thư viện 64-bit chưa căn 16 KB (`libimage_processing_util_jni.so`, `libface_detector_v2_jni.so`, `libxeno_native.so` bản x86_64).
- **Fizahub 2.0.5** bật `usesCleartextTraffic` cho toàn app.

### Chưa kiểm chứng

- `bundletool validate` và "Xuất APK universal" mới chạy với process giả trong test; chưa chạy với bundletool thật vì máy chưa tải jar. Bấm "Tải bundletool" trong module rồi thử một lần.
- Kéo-thả từ Explorer (`desktop_drop`, plugin native mới) cần build lại bản Windows mới chạy được; widget test không giả lập được thao tác kéo của hệ điều hành.

## 1. Những gì code và máy này cho biết

Đây là các ràng buộc thật, không phải giả định:

- **Build release có thể âm thầm ký bằng debug key.** Template Gradle trong `android_cicd_clone_service.dart` (dòng 661 và 721) chỉ `logger.warn` rồi dùng debug signing khi `android/env.properties` thiếu keystore. Build vẫn xanh, AAB vẫn ra. Đây là kiểm tra số một của nhóm Build.
- **Release workflow đã tách Build AAB và Deploy** (`release_workflow_service.dart:224`). Có sẵn chỗ để cắm một bước kiểm tra chặn trước khi upload.
- **Bot Telegram hiện chỉ gửi, chưa từng đọc.** `TelegramReleaseNotificationService` chỉ gọi `sendMessage` và `sendDocument`, host `api.telegram.org` viết cứng (dòng 420, 453). Relay không dùng Telegram, nên `getUpdates` không đụng webhook nào của repo này.
- **Cloud Bot API chỉ cho bot tải file ≤ 20 MB.** AAB Flutter mang ba ABI nên thường vượt mốc này. File > 50 MB hiện đã đi đường Google Drive (OAuth có sẵn). Xem mục 5.2 — đây là quyết định lớn nhất của cả plan.
- **Máy này:** có `adb`, hai thiết bị thật đang cắm (`6471f270`, `R5CXA1X0GLW`), AVD `ZFold_3`, build-tools tới 36.1 (có `apksigner`, `aapt2` nhưng không nằm trên PATH), JDK 21, `keytool`. **Không có `bundletool`.** `emulator` không trên PATH, `ANDROID_HOME` trống — phải tự dò `%LOCALAPPDATA%\Android\Sdk`.
- **Dependency:** `archive` đã có nên đọc zip bằng Dart thuần được. Chưa có package kéo-thả cho desktop — cần thêm `desktop_drop`.
- **Env của app đích chưa rõ.** Lệnh build trong template không truyền `--dart-define`. `android/env.properties` chỉ phục vụ Gradle và Fastlane, không vào bundle. Env phía Dart phụ thuộc từng app — xem câu hỏi mở 2.

## 2. Luồng tổng

```
 Kéo-thả vào AMC ─┐
 Bot Telegram ────┼─► Nhận file ─► Đọc bundle ─► Kiểm Build ─► Kiểm Env ─► Chạy thử ─► Báo cáo
 Bước workflow ───┘   (job dir,    (Dart thuần    (B01–B13)    (E01–E06)   (R01–R07,   (AMC +
   (Phase 4)          SHA-256,     + bundletool                             tuỳ chọn)   reply Telegram)
                      chặn trùng)  dump)
```

Mỗi lần kiểm là một job, thư mục riêng `<appSupport>/bundle_checks/<jobId>/`: `input.aab`, `device.apks`, `manifest.xml`, `resources.txt`, `logcat.txt`, `screen_*.png`, `report.json`. Giữ 20 job gần nhất; job cũ hơn xoá file lớn, giữ `report.json` để so sánh.

Job tự gắn với project bằng package name (`ChPlayProjectInspectorService.detectApplicationId`). Không khớp project nào thì vẫn chạy, chỉ bỏ qua các kiểm tra cần contract của project (hiện `SKIP`, không phải `PASS`).

## 3. Các kiểm tra

Mỗi kết quả có một trong bốn trạng thái: `PASS`, `WARN`, `FAIL`, `SKIP` — kèm chi tiết và gợi ý sửa. `SKIP` luôn ghi lý do, không để người đọc tưởng là đã qua.

### 3.1 Build đúng không

| ID | Kiểm tra | Cách làm | Sai thì |
|---|---|---|---|
| B01 | File là AAB hợp lệ | Zip mở được, có `BundleConfig.pb` và `base/manifest/AndroidManifest.xml`; `bundletool validate` | FAIL |
| B02 | Package đúng app | So với applicationId của project | FAIL |
| B03 | Version | versionName/versionCode khớp pubspec (WARN); versionCode **lớn hơn** bản mới nhất trên CH Play theo `ChPlayVersionCheckService` (FAIL — Play sẽ từ chối) | WARN / FAIL |
| B04 | Chữ ký | `keytool -printcert -jarfile` lấy SHA-256. Chủ thể `CN=Android Debug` → FAIL. Khác fingerprint upload key đã ghim của project → FAIL. Ghim lần đầu từ keystore trong `env.properties` (`keytool -list -v`) | FAIL |
| B05 | Không phải bản debug | `debuggable` không bật, không `testOnly` | FAIL |
| B06 | Flutter build ở chế độ release | Có `lib/<abi>/libapp.so` và `libflutter.so`; không có `flutter_assets/kernel_blob.bin` | FAIL |
| B07 | ABI | Có `arm64-v8a` (yêu cầu 64-bit). Thiếu `x86_64` thì cảnh báo trước là emulator sẽ không chạy được | FAIL / WARN |
| B08 | 16 KB page size | Đọc ELF header mọi `.so`, mọi `PT_LOAD` phải có `p_align ≥ 16384`. Play bắt buộc với targetSdk ≥ 35 | FAIL |
| B09 | targetSdk | ≥ ngưỡng chính sách Play. Ngưỡng để trong cấu hình, không viết cứng — kiểm lại chính sách hiện hành khi triển khai | FAIL |
| B10 | Permission mới | So với lần kiểm trước cùng package; permission nguy hiểm mới xuất hiện được tô đậm | WARN |
| B11 | Kích thước | `bundletool get-size total`; tăng > 15% so với lần trước | WARN |
| B12 | Mapping R8 | Có `BUNDLE-METADATA/.../proguard.map` để giải mã crash trên Play Console | INFO |
| B13 | Cleartext | `usesCleartextTraffic="true"` trong bản release | WARN |

### 3.2 Đủ env không

AAB không có khái niệm "env". Env rơi vào bundle ở bốn chỗ khác nhau, nên phải soi cả bốn. Mỗi project có một **env contract** lưu trong `ProjectStoreService`: tự sinh lần đầu từ `.env.example` và `android/app/google-services.json` của project, sau đó người dùng chỉnh. Contract gồm: key bắt buộc, giá trị mong đợi (vd Firebase project_id của prod), chuỗi bắt buộc có, chuỗi cấm có.

| ID | Kiểm tra | Cách làm | Sai thì |
|---|---|---|---|
| E01 | Env trong Flutter assets | Đọc `base/assets/flutter_assets/` tìm `.env*`, `assets/**/*.env`, file config JSON. So key với contract: thiếu, rỗng, còn placeholder (`changeme`, `xxx`, `TODO`, `your_...`) | FAIL |
| E02 | Trỏ đúng môi trường | Giá trị chứa `localhost`, `127.0.0.1`, `10.0.2.2`, `ngrok`, hoặc chuỗi cấm của contract (vd host staging) | FAIL |
| E03 | Firebase native | `bundletool dump resources --values` lấy `google_app_id`, `project_id`, `gcm_defaultSenderId`, `google_api_key`, `default_web_client_id`. Pubspec có Firebase mà thiếu → FAIL; `project_id` khác contract → FAIL | FAIL |
| E04 | Manifest meta-data | Key Maps, Facebook app id, v.v. rỗng hoặc còn `${...}` chưa thay | FAIL |
| E05 | `--dart-define` / `firebase_options.dart` | Giá trị bị compile vào `libapp.so`. Quét chuỗi trong `libapp.so` (arm64) tìm chuỗi bắt buộc và chuỗi cấm của contract | WARN |
| E06 | Lộ bí mật | Key tên `SECRET` / `PRIVATE` / `PASSWORD` / `SERVICE_ACCOUNT`, hoặc giá trị giống private key / JSON service account nằm trong assets — ai có APK cũng đọc được | WARN |

E05 chỉ là heuristic nên dừng ở WARN, và báo cáo phải nói rõ giới hạn: `envied(obfuscate: true)` mã hoá giá trị nên không kiểm được bằng cách này.

Giá trị env **luôn hiển thị dạng che** (`ab••••yz`) trong AMC và **không bao giờ** được gửi lên Telegram.

### 3.3 Chạy được không

"Chạy được" ở đây nghĩa là: cài được, mở lên, không crash trong N giây. Không phải test chức năng.

| ID | Bước | Cách làm |
|---|---|---|
| R01 | Chọn thiết bị | Serial hoặc AVD đã cấu hình. AVD chưa chạy thì bật `emulator -avd <tên> -no-snapshot-save`, chờ `sys.boot_completed=1` (tối đa 180 giây) |
| R02 | Sinh APK | `bundletool build-apks --connected-device --device-id <serial>`, ký bằng upload keystore của project. Mật khẩu truyền qua `--ks-pass=file:<file tạm>` rồi xoá ngay — không đưa lên argv. Không có keystore thì dùng debug keystore và ghi rõ trong báo cáo |
| R03 | Cài | `bundletool install-apks --allow-downgrade`. Gặp `INSTALL_FAILED_UPDATE_INCOMPATIBLE` (khác chữ ký): emulator thì tự gỡ rồi cài lại; máy thật thì hỏi trong AMC vì gỡ là mất dữ liệu app; job từ Telegram thì dừng và báo |
| R04 | Mở | Tìm launcher activity (`cmd package resolve-activity --brief`), `logcat -c`, `am start -W` → lấy `TotalTime` làm thời gian cold start |
| R05 | Theo dõi | 20 giây (cấu hình được): process còn sống không (`pidof`); `logcat -b crash` và `logcat --pid` tìm `FATAL EXCEPTION`, `ANR in`, `UnsatisfiedLinkError`, `ClassNotFoundException` / `NoSuchMethodError` (dấu hiệu R8 cắt nhầm — lỗi chỉ có ở bản release), `E/flutter` + `Unhandled Exception`, `MissingPluginException` |
| R06 | Ảnh màn hình | `exec-out screencap -p` lúc 3 giây và lúc kết thúc. Ảnh gần như một màu → WARN "có thể kẹt ở splash hoặc màn trắng" |
| R07 | Dọn | `force-stop`; gỡ app nếu chính job này đã cài lên emulator (cấu hình được) |

Giới hạn phải in trong mọi báo cáo có chạy thử: APK được ký lại bằng upload key hoặc debug key, **không phải** Play app signing key. Google Sign-In, Maps, App Check — những thứ gắn SHA-1 — có thể lỗi khi chạy local trong khi bản trên Play vẫn đúng.

## 4. Nguồn 1 — Ném file vào AMC

- Module mới `lib/app/modules/bundle_check/`, cùng bố cục với `mail_cleaner` (controllers / models / services / views / widgets).
- Mở từ command palette ("Kiểm tra AAB") và menu tràn của flow panel, cạnh "Dọn hộp thư".
- Vùng thả file dùng `desktop_drop`; nút chọn file dùng `file_picker` sẵn có. Nhận `.aab` (đầy đủ), `.apk` (bỏ B01, B11, R02), `.apks`.
- Nhiều project khớp package, hoặc không khớp cái nào → dropdown chọn, có lựa chọn "Không gắn project".
- Màn kết quả: ba cột Build / Env / Chạy; tab Manifest, Env (đã che), Logcat, Ảnh. Hai nút phụ:
  - **Chỉ kiểm tĩnh** — không đụng thiết bị, xong trong vài giây.
  - **Xuất APK universal** (`build-apks --mode=universal`) — ra một APK cài được trên mọi máy để gửi tester.

## 5. Nguồn 2 — Bot Telegram

### 5.1 Bot nhận file thế nào

AMC dùng lại bot token trong `TelegramCredentialStoreService` và long-poll `getUpdates` (timeout 25 giây, lưu offset). Telegram giữ update 24 giờ, nên AMC tắt rồi mở lại vẫn xử lý bù được.

Bốn cách kích hoạt:

1. **Reply `/check` vào tin có file `.aab`/`.apk`.** Chạy được cả khi privacy mode đang bật: bot luôn nhận command, và `reply_to_message` mang theo document. Đây là cách mặc định.
2. **Gửi file thẳng cho bot** trong chat riêng.
3. **Tự kiểm mọi AAB trong group** (tuỳ chọn): phải tắt privacy mode ở BotFather rồi add lại bot, hoặc cho bot làm admin.
4. **Tin có link Google Drive** (luồng fallback > 50 MB đang có) → tải bằng Drive API qua OAuth đã kết nối.

Chỉ nhận từ chat ID và user ID trong allowlist; ngoài danh sách thì im lặng bỏ qua. Chặn kiểm trùng bằng `file_unique_id` và SHA-256.

### 5.2 Mốc 20 MB — phải chọn một đường

| | A. Local Bot API server | B. Luôn đi qua Google Drive | C. Chỉ file ≤ 20 MB |
|---|---|---|---|
| Tải được | Không giới hạn | Không giới hạn | ≤ 20 MB |
| Gửi được (bonus) | Tới 2000 MB — bỏ luôn được Drive fallback cho APK | Như hiện tại | Như hiện tại |
| Cần thêm | Server `telegram-bot-api` chạy trên máy (Docker hoặc WSL), `api_id`/`api_hash` từ my.telegram.org | Người gửi phải đẩy AAB lên Drive rồi gửi link | Không |
| Cái giá | Gọi `logOut` một lần để chuyển bot khỏi cloud; từ đó **mọi** gọi Telegram của AMC, kể cả thông báo release, đi qua server local — server tắt là mất thông báo | Đổi thói quen người gửi | Gần như không dùng được cho AAB |

**Đề xuất A**, vì nó giải luôn giới hạn 50 MB đang phải vòng qua Drive. Dù chọn đường nào, host Telegram đang viết cứng phải thành cấu hình (AAB-010).

### 5.3 Trả kết quả

- Nhận file là reply ngay "⏳ Đang kiểm tra app-release.aab (42 MB)…", xong thì `editMessageText` chính tin đó thành kết quả: dòng tóm tắt, tối đa năm lỗi đầu, thời gian cold start. Ảnh màn hình gửi dạng photo; `report.html` đầy đủ gửi dạng document nếu bật.
- Không bao giờ gửi giá trị env, mật khẩu keystore, hay đường dẫn trên máy.
- Mỗi lúc một job — thiết bị là tài nguyên dùng chung. Job sau nhận "Đang xếp hàng (#2)". Có `/status` và `/cancel`.

### 5.4 An toàn

- **File từ Telegram là không tin cậy**; cài nó lên thiết bị là chạy code lạ. Mặc định job từ Telegram chỉ chạy thử trên emulator; muốn chạy trên máy thật phải bật riêng.
- Giải nén không bao giờ ghi file theo tên entry (chống zip-slip), có trần tổng dung lượng giải nén (chống zip bomb), và không chạy bất cứ thứ gì trong bundle trên máy Windows.

## 6. Kiến trúc code

```
lib/app/modules/bundle_check/
  models/
    bundle_check_report.dart      CheckResult, BundleFacts, BundleCheckReport
    env_contract.dart
    bundle_check_settings.dart    thiết bị, số giây theo dõi, allowlist, cách kích hoạt
  services/
    android_toolchain_locator.dart   SDK, build-tools mới nhất, adb, emulator, java
    bundletool_manager.dart          tải jar ghim phiên bản + SHA-256 vào app support
    bundle_archive_reader.dart       Dart thuần: entry, flutter_assets, ELF p_align, chuỗi trong libapp.so
    bundletool_client.dart           validate / dump / get-size / build-apks / install-apks
    signature_inspector.dart         keytool
    checks/build_checks.dart         hàm thuần: BundleFacts + context → List<CheckResult>
    checks/env_checks.dart           hàm thuần: BundleFacts + EnvContract → List<CheckResult>
    device_smoke_runner.dart
    bundle_check_service.dart        điều phối, hàng đợi, huỷ, timeout từng bước, dọn job cũ
    telegram_bundle_intake_service.dart
  controllers/bundle_check_controller.dart
  views/  widgets/
```

- **Kiểm tra là hàm thuần**, giống `powerCommandRejection(...)` bên remote control: nhận facts đã đọc sẵn, trả danh sách kết quả, test không cần tool nào.
- **Chạy process qua một abstraction fake được**, cùng kiểu `CiCdCommandProbe`. **Không** đi qua `ReleaseRunnerService`, để kiểm AAB không chiếm `runner.isBusy` và không chặn release.
- **Doctor:** thêm check `bundletool` và `android-emulator` vào `CiCdDependencyDoctorService`; tái dùng check build-tools và platform-tools sẵn có.
- **Telegram:** tách phần gọi Bot API khỏi `TelegramReleaseNotificationService` thành một client dùng chung có thêm `getUpdates`, `getFile`, tải file, `editMessageText`, `sendPhoto`, và base URL cấu hình được.

## 7. Các phase

Phase 1 đứng độc lập và dùng được ngay; Phase 2 và 3 dựng trên nó. Telegram để sau cùng vì phụ thuộc quyết định ở 5.2.

**Phase 1 — Kiểm tĩnh trong AMC**
- AAB-001: toolchain locator + bundletool manager + check trong doctor.
- AAB-002: archive reader (entry, assets, ELF, chuỗi) + chống zip-slip / zip bomb.
- AAB-003: B01–B13.
- AAB-004: env contract (tự sinh + màn chỉnh) + E01–E06.
- AAB-005: màn kéo-thả, màn báo cáo, lịch sử job, xuất APK universal.
- AAB-006: gắn vào command palette và flow panel.

**Phase 2 — Chạy thử**
- AAB-007: cài đặt thiết bị kiểm thử + bật AVD và chờ boot.
- AAB-008: build-apks → cài → mở → theo dõi logcat (R02–R05).
- AAB-009: ảnh màn hình, dọn, đưa kết quả chạy vào báo cáo (R06–R07).

**Phase 3 — Telegram**
- AAB-010: client Bot API dùng chung + base URL cấu hình.
- AAB-011: intake: poll, allowlist, bốn cách kích hoạt, chặn trùng.
- AAB-012: đường tải file theo quyết định 5.2.
- AAB-013: reply / edit / ảnh, hàng đợi, `/status`, `/cancel`.

**Phase 4 — Gắn vào release**
- AAB-014: bước "Kiểm tra AAB" giữa Build AAB và Deploy. FAIL chặn deploy; có nút bỏ qua, và bỏ qua được ghi vào log.
- AAB-015: gửi tóm tắt kết quả kiểm cùng release note lên Telegram.

## 8. Kiểm chứng

- Unit test cho B*/E* bằng `BundleFacts` dựng tay.
- Test parser ELF bằng header `.so` tự dựng vài trăm byte, cả bản căn 4 KB lẫn 16 KB.
- Test reader với zip sinh ngay trong test (package `archive`): entry `../../evil`, entry khai báo nhỏ nhưng giải nén rất lớn.
- Test intake với `TelegramHttpClient` giả: ngoài allowlist, reply `/check`, file > 20 MB, trùng `file_unique_id`, lưu offset.
- Integration test chỉ chạy khi có biến môi trường, giống `STUDIO_SCREENSHOTS`: `AAB_CHECK_FIXTURE=<đường dẫn .aab>` chạy bundletool thật; thêm `AAB_CHECK_DEVICE=<serial>` thì chạy thử thật trên thiết bị.
- Kiểm thủ công với bốn AAB mẫu, mỗi cái phải ra đúng FAIL của nó:
  1. Build chuẩn → không có FAIL.
  2. Xoá keystore khỏi `env.properties` rồi build → B04 FAIL (ký debug).
  3. Xoá một key khỏi `.env` rồi build → E01 FAIL.
  4. Thêm `throw` trong `main()` rồi build → R05 FAIL.

## 9. Câu hỏi mở

1. **Mốc 20 MB:** chọn A, B hay C ở mục 5.2? Đề xuất A.
2. **Các app của bạn đưa env vào bằng cách nào?** `.env` asset (flutter_dotenv), `--dart-define` / `--dart-define-from-file`, `envied`, hay flavor + `google-services.json` riêng? Câu trả lời quyết định E01 hay E05 là kiểm tra chính.
3. **Bot này có đang bị dịch vụ khác đọc update không** (webhook, hoặc một chương trình khác cũng poll)? Nếu có, `getUpdates` sẽ trả 409 và phải dùng bot riêng cho việc kiểm.
4. **Chạy thử trên đâu:** emulator `ZFold_3` hay một trong hai máy thật đang cắm? Có project nào giới hạn `abiFilters` chỉ ARM không — nếu có thì emulator x86_64 không chạy được.
5. **Ai được gửi file cho bot kiểm:** chỉ bạn, hay cả nhóm dev?
