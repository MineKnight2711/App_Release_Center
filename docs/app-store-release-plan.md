# Kế hoạch release iOS: TestFlight, App Store và script

Ngày: 2026-10-12. Trạng thái: đã triển khai workflow trong AMC và xuất script;
đã kiểm tra bằng test và Fastlane với API giả lập. Upload/review thực tế trên
Apple cần được kiểm tra bằng lần release do người dùng chọn.

## Cách sử dụng bản đã triển khai

Trong card App Store, bấm biểu tượng tên lửa **Release TestFlight / App Store**.
Nút **Chạy release** của project đã setup iOS cũng cho chọn iOS hoặc Android.
Dialog iOS dùng cùng khung với luồng CH Play: màn chuẩn bị, rồi màn theo dõi
có timeline 7 bước (Preflight → Build IPA → Upload → Apple xử lý → App Store →
Review → Phát hành), chi tiết bước, log và một nút chính cho bước kế tiếp.

1. **Cấu hình build** (một lần cho project): flavor (scheme/configuration tự
   suy ra), entrypoint, Team ID, ExportOptions plist, build arguments (mỗi dòng
   một flag), TestFlight groups, external testing, locale release notes và
   chế độ tự phát hành. Locale mặc định là `vi-VN`, gửi sang Apple bằng mã
   `vi`; có thể dùng ngôn ngữ chính trên App Store Connect. AMC chỉ cập nhật
   “What's New” của locale đã có, không tạo ngôn ngữ hoặc sửa App Information.
   **Xuất script iOS** nằm trong dialog này.
2. Màn chuẩn bị: chọn **Build mới** hoặc **Build TestFlight có sẵn** (chọn rõ
   một build VALID, không tự chọn build mới nhất), nhập marketing version và
   release notes, rồi **Xem lại release**: AMC kiểm tra API, signing và chốt
   build number. Version/build chỉ truyền cho Flutter, không ghi pubspec.
3. **Build & upload TestFlight** chạy build IPA → upload → theo dõi processing
   liên tiếp, dừng ở bước lỗi đầu tiên. **Chạy lại bước lỗi** tiếp tục từ đó,
   không build lại IPA đã có. Artifact, archive, manifest và log nằm trong thư
   mục riêng cho run; log của run hiển thị ngay trong dialog.
4. Khi build VALID: **Phân phối TestFlight** tới groups (nếu đã cấu hình), hoặc
   **Chuẩn bị App Store** gắn đúng build vào draft. **Gửi review** và
   **Phát hành** là thao tác riêng, luôn hỏi xác nhận kèm version/build/notes.
5. Thao tác phụ (chỉ build IPA, làm mới Apple, thử upload lại, mở IPA, release
   mới) nằm trong menu **…**; lịch sử các run ở biểu tượng đồng hồ trên header.

Lịch sử được khôi phục khi mở lại dialog; có thể ẩn dialog khi đang chạy và mở
lại để theo dõi tiếp. AMC không tự chạy lại lệnh upload, review hay phát hành.
Nếu upload bị gián đoạn, **Kiểm tra lại Apple** trước; thao tác thử upload lại
yêu cầu người dùng xác nhận đã kiểm tra lần trước.

## Quyết định

AMC quản lý cấu hình, chuẩn bị version, build, upload và theo dõi release.
Flutter tạo IPA; Fastlane thực hiện các thao tác App Store Connect bằng API key
đã lưu trong AMC. Project không bắt buộc có `auto/` hoặc `ios/fastlane/`.
Fastfile được tạo từ mẫu chung trong workspace của lần chạy, với cấu trúc
`fastlane/Fastfile`; dùng đường dẫn tuyệt đối tới project, IPA và metadata.

Script chạy riêng là tùy chọn xuất từ cùng bộ mẫu, không duy trì một workflow
release iOS khác cho từng repo. Chỉ thêm cấu hình riêng khi project có flavor,
entrypoint, signing hoặc bước chuẩn bị đặc thù.

Phạm vi đầu tiên là app iOS build trên macOS. App macOS dùng PKG là phạm vi khác.

## Hiện trạng đã kiểm tra

- `AppStoreVersionCheckService` đọc `pubspec.yaml` và lấy build TestFlight theo
  version; chưa đọc version đang phát hành trên App Store và trạng thái review.
- `ReleaseWorkflowService`, cấu hình workflow và dialog hiện gắn với CH Play.
- `ScriptCatalogService` chỉ đọc `android/fastlane/Fastfile`; runner cũng chọn
  thư mục Android khi chạy lane. Cần bổ sung nguồn iOS cho chế độ script.
- Năm project dưới đây có script `auto/` và Android Fastfile, nhưng chưa có
  iOS Fastfile hoặc ExportOptions plist theo tên đã khảo sát. `deploy.sh` chưa
  có lệnh build/upload iOS.

| Project | Bundle ID app trong Xcode | Team ID | Hướng cập nhật |
|---|---|---|---|
| `emed_plus_new` | `com.emed.globerdr` | `9KXDDLUB3Y` | Pilot workflow AMC, cấu hình signing iOS |
| `VNetrip_4_0` | `com.tpv.vnetrip` | `VK682LPC87` | Dùng workflow chung, cấu hình riêng |
| `sigland_mobile` | `vn.sigland.app` | `VK682LPC87` | Dùng workflow chung, cấu hình riêng |
| `fizahub_app` | `vn.fizahub.app` | `P25PFHHFP6` | Chọn repo nguồn cho lần release |
| `fizahub_mobile` | `vn.fizahub.app` | `P25PFHHFP6` | Dùng chung lịch sử build với `fizahub_app` |

Đây là giá trị trong source, chưa xác minh quyền API, certificate hoặc profile
trên máy. Các Xcode project có nhiều bundle ID, gồm test target hoặc cấu hình
khác; preflight phải lấy build settings của scheme/configuration được chọn,
không lấy bundle ID đầu tiên trong file. Hai repo Fizahub cần khóa chạy theo
team + bundle ID, và lịch sử hiển thị rõ repo/commit tạo build.

`kysocccd` và `GEMR_Kiosk` có thư mục iOS, chưa có script `auto/`; kiến trúc AMC
phải cho phép onboard các project như vậy mà không đòi bộ script Android.

## Thiết lập một lần cho từng project

Lưu Bundle ID, Team ID, scheme/configuration, entrypoint, flavor nếu có,
Flutter executable và build arguments dạng danh sách. Signing có chế độ
Automatic hoặc dùng ExportOptions plist do project cung cấp. Chỉ lưu đường
dẫn/config; certificate và private key signing ở Keychain hoặc cơ chế signing
đã cấu hình. API key `.p8` dùng truy cập Apple, không thay certificate signing.

Preflight xác minh macOS, Xcode được chọn, Flutter, dependencies, Fastlane hoặc
Bundler, credential, app record trên Apple, effective Bundle ID/Team ID và
signing. Báo thiếu chính xác trước khi build. Enterprise/in-house không phải
đích TestFlight/App Store của workflow này.

Lưu thêm cấu hình TestFlight groups, nội dung “What to Test”, các locale release
notes và chế độ App Store: chuẩn bị bản phát hành, gửi review, phát hành thủ công
hoặc tự động sau duyệt. Không tự điền các câu trả lời compliance/metadata chưa
được người dùng cấu hình. V1 tận dụng thông tin đã có trên App Store Connect.

## Luồng TestFlight

1. Chuẩn bị: đọc Git branch/commit, working tree, local version, build trên
   Apple; hiển thị đề xuất version/build và những file dự kiến thay đổi.
2. Version: giữ marketing version mặc định; build số nguyên đề xuất bằng
   `max(localBuild, latestTestFlightBuildForVersion + 1)`, tăng thêm khi build
   đã tồn tại. Phải đọc remote thành công; không lấy 0 khi query bị lỗi.
   Kiểm tra lại trước upload và khóa theo app để tránh hai repo đụng build.
3. Tạo release notes; người dùng có thể sửa. Commit/push là lựa chọn riêng;
   không gọi script Android tăng version hoặc commit chỉ để release iOS.
4. Build IPA từ root project bằng `flutter build ipa --release` với
   `--build-name`, `--build-number` và export options tương ứng. Nếu chọn cập
   nhật `pubspec.yaml`, chỉ ghi thay đổi đã preview và giữ nguyên phần khác.
5. Lưu IPA/archive và manifest: run ID, source repo, commit/dirty state,
   Bundle ID/Team ID, version/build, arguments, IPA hash và kết quả từng bước.
6. Upload đúng IPA bằng `upload_to_testflight`; theo dõi processing thành bước
   riêng. Upload thành công chưa đồng nghĩa build đã sẵn sàng cho tester.
7. Phân phối tới group được chọn sau khi build sẵn sàng. External testing có
   beta review riêng; mặc định không tự phân phối ra external groups.
8. Refresh snapshot, ghi lịch sử và gửi thông báo qua cơ chế release hiện có.

Timeout processing giữ trạng thái “đang xử lý/chờ xác minh”, có thể tiếp tục
poll sau; không build/upload lại chỉ vì hết thời gian chờ. Khi retry upload
sau lỗi mạng, query chính xác version/build trên Apple trước để tránh upload
trùng. Nếu Apple từ chối build, báo nguyên nhân và chuẩn bị build mới.

## Luồng App Store

Có hai điểm bắt đầu: dùng build TestFlight đã sẵn sàng, hoặc build/upload mới.
UI chọn rõ version/build và hiển thị repo/commit nếu AMC có lịch sử tương ứng.
Không tự chọn “latest” vì có thể là build của repo hoặc lần chạy khác.

1. Đọc version live, version đang chuẩn bị/review và build đã chọn trên Apple.
2. Hiển thị release notes theo locale, thông tin còn thiếu và trạng thái build.
3. Chuẩn bị version App Store, cập nhật phần metadata được cấu hình. Tái dùng
   build có sẵn qua `upload_to_app_store(skip_binary_upload: true,
   app_version: ..., build_number: ...)`.
4. Mặc định lưu bản chuẩn bị với `submit_for_review: false`. Nút “Gửi review”
   là thao tác riêng với bản preview cụ thể; hỗ trợ `automatic_release: false`
   mặc định và chế độ tự động nếu người dùng chọn.
5. Theo dõi review, rejected, pending developer release và ready for sale.
   “Gửi review thành công” và “đã phát hành” là hai kết quả khác nhau.

Đợt đầu chỉ cần chuẩn bị version và chọn build, hoàn tất review/phát hành trên
App Store Connect khi cần. Bổ sung thao tác gửi review/phát hành trong AMC sau
khi có preflight metadata và xử lý trạng thái tương ứng.

## Script và cập nhật project

Không cần sửa `auto/release.sh`, `deploy.sh`, `control_ver_code.sh` hay Android
Fastfile để dùng workflow AMC. Các script đó đang dùng Google Play để quyết
định version; gọi lại cho iOS sẽ chọn sai nguồn build number.

Chế độ xuất script tạo bộ độc lập:

- `auto/release_ios.sh`: wrapper không tương tác, gọi đúng Flutter/Fastlane,
  tách bước build, upload TestFlight và chuẩn bị App Store.
- `ios/fastlane/Fastfile`: sinh từ cùng mẫu phiên bản với AMC, nhận đầy đủ đường
  dẫn, version/build và chế độ release; không chứa secret.
- Config mẫu với scheme, flavor, entrypoint, signing và các tham số công khai.
  API key nhận qua file ngoài repo/environment; không nhúng khóa đã lưu AMC.

Script đã xuất chạy được bằng terminal mà không cần app đang mở. AMC có thể
gọi script riêng của project theo hợp đồng input/output, nhưng phải chọn chế
độ rõ ràng; không tự động chạy lane tùy ý thay cho workflow đã preview.
Xuất ra vùng preview trước, so diff rồi mới áp dụng vào repo. Không ghi đè
Fastfile/script có sẵn; cập nhật phần được AMC quản lý theo version của mẫu.

Với năm project khảo sát, bản đầu chỉ thêm cấu hình trong AMC. Khi cần chạy
terminal/CI, mới xuất bộ iOS độc lập vào project đó.

## Thay đổi trong AMC

- Thêm model `IosReleaseConfig` và `IosReleaseRun` riêng cho iOS, tái dùng
  trạng thái bước/log/artifact hiện có. Tránh buộc iOS cung cấp `ChPlayProject`
  hoặc phụ thuộc script version Android; chưa cần refactor toàn bộ CH Play.
- Thêm `IosReleaseWorkflowService`, service build IPA, store query/upload,
  mẫu Fastfile chung và lịch sử run bền vững. Credentials chỉ nạp khi chạy;
  file khóa tạm xóa khi hoàn tất, lỗi hoặc hủy, không lưu trong manifest/log.
- Mở rộng snapshot để phân biệt local, TestFlight và App Store live/draft.
- Thêm nút TestFlight/App Store trong card project và chọn nền tảng trong
  release dialog; mỗi đích có bước và kết quả riêng.
- Catalog/lane model cần giữ nguồn Fastfile/thư mục làm việc và nền tảng.
  Runner chọn iOS/Android từ nguồn lane, không hardcode Android; lane key
  bao gồm nguồn để tránh trùng tên.
- Retry tiếp tục từ bước lỗi, giữ artifact/run manifest; sau restart khôi phục
  lịch sử nhưng không tự chạy lại upload, submit review hoặc release.

## Thứ tự triển khai và nghiệm thu

1. **TestFlight trong AMC:** config + preflight + version + IPA + upload +
   processing + lịch sử/retry. Pilot `emed_plus_new`. Nghiệm thu bằng một build
   được cho phép upload, đúng Bundle ID/version/build và sẵn sàng trên Apple.
2. **App Store:** query live/draft/review, chọn lại build TestFlight, chuẩn bị
   release notes/version; tiếp đến submit review và phát hành theo lựa chọn.
   Nghiệm thu bằng build cụ thể được gắn vào đúng version, không upload lại.
3. **Các project còn lại và script:** onboard Team/signing từng project;
   kiểm tra khóa cùng Bundle ID ở hai repo Fizahub; xuất script tùy nhu cầu.

Test cần bao phủ version collision, signing thiếu, flavor/entrypoint, chạy
Bundler/global, Fastfile discovery, export IPA, Apple API lỗi, processing
timeout, retry upload sau lỗi mạng, tiếp tục bằng IPA cũ, App Store chọn đúng
build, cleanup secret khi hủy và hồi phục sau restart. Kiểm tra CH Play hiện
có vẫn hoạt động và project thiếu `auto/` vẫn dùng được workflow iOS.

## Tài liệu tham chiếu

- [Flutter: build và release iOS](https://docs.flutter.dev/deployment/ios)
- [Fastlane: upload TestFlight](https://docs.fastlane.tools/actions/upload_to_testflight/)
- [Fastlane: latest TestFlight build](https://docs.fastlane.tools/actions/latest_testflight_build_number/)
- [Fastlane: chuẩn bị và submit App Store](https://docs.fastlane.tools/actions/upload_to_app_store/)
