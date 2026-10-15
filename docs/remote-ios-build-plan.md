# Build iOS từ Windows qua Mac build host

Ngày: 2026-10-15. Trạng thái: đã triển khai trong AMC và relay. Đã kiểm tra
bằng test với git thật và relay thật chạy local (Xcode, Flutter, Fastlane
được giả lập). **Chưa chạy trên Mac mini thật**, cần thử một lần release
thật trước khi dùng thường xuyên.

Mục tiêu: máy Windows là nơi điều khiển, Mac mini là máy build. Bấm
**Build & upload TestFlight** trên AMC Windows, Mac mini build, ký, upload,
còn timeline và log chạy trên Windows. Không cần remote desktop.

## Thiết lập một lần trên Mac mini

1. Cài AMC bản mới trên Mac. Đăng nhập phiên GUI và để AMC chạy, có thể chạy
   nền. Mac không được ngủ: System Settings → Energy → bật *Prevent automatic
   sleeping when the display is off*.
2. **Tuỳ chọn → Thông báo**: dùng cùng relay endpoint và Desktop API token
   với máy Windows.
3. **Tuỳ chọn → Điều khiển từ xa**: bật *Trung chuyển lệnh từ điện thoại* và
   *Nhận build iOS từ máy khác*. Mac tự lấy id riêng `mac-<tên máy>`, để
   không tranh lệnh với máy Windows đang dùng id `default`.
4. Bấm **Ghép máy điều khiển build**. Mac hiện mã ghép 8 ký tự cùng mã khoá
   (ví dụ `3F2A-91C0-7B11-E4D2`).
5. Công cụ trên Mac: Xcode, Flutter, CocoaPods, Fastlane (hoặc Bundler nếu
   project có Gemfile). Keychain đăng nhập phải có certificate Apple
   Distribution kèm private key. Bước preflight kiểm tra những thứ này.
6. Mac cần quyền đọc repo: SSH key đã nạp vào ssh-agent/Keychain, hoặc
   credential helper cho https. AMC chạy git với `GIT_TERMINAL_PROMPT=0` và
   `ssh -o BatchMode=yes`, vì không có ai ngồi trước Mac để nhập mật khẩu.
   Thiếu quyền thì git báo lỗi ngay, không treo.

## Trên máy Windows

1. Card App Store → biểu tượng tên lửa → dialog iOS. Thẻ **Máy build** →
   **Ghép Mac** → nhập mã. AMC hiện mã khoá, so khớp với mã trên Mac.
2. **Cấu hình build** → *File gửi kèm khi build trên Mac*: mỗi dòng một file
   đã gitignore mà build cần, như `.env` hoặc
   `ios/Runner/GoogleService-Info.plist`.
3. Commit và push. Thẻ Máy build hiện commit Mac sẽ build. Nếu commit chưa
   thấy trên remote, hoặc còn file chưa commit (những file này sẽ không được
   build), thẻ sẽ cảnh báo.
4. **Xem lại release** → **Build & upload TestFlight** như khi build trên
   Mac. Có thể đóng dialog trong lúc chạy; mở lại thì AMC theo dõi tiếp,
   kể cả sau khi khởi động lại app.

Máy Windows vẫn rảnh trong lúc Mac build, nên có thể chạy release Android
cùng lúc.

## Thiết kế

- **Kênh**: relay Cloudflare sẵn có (`amc-relay`), dùng được khi hai máy ở
  khác mạng. Thêm hai loại lệnh:
  - `ios`: lane release, mỗi lệnh là một bước của workflow.
  - `iosQuery`: lane control, chỉ đọc lịch sử và log, nên vẫn trả lời được
    khi Mac đang build.
- **Quyền**: scope mới `ios`. Mã ghép gắn với `desktopId` của Mac. Relay chỉ
  cho thiết bị gửi lệnh `ios` tới đúng Mac đã tạo mã, nên điện thoại có scope
  `run` hay thiết bị do máy khác ghép đều bị từ chối (403).
- **Mã hoá đầu-cuối**: mỗi bước được niêm phong bằng X25519 + HKDF-SHA256 +
  AES-256-GCM, gửi tới khoá của Mac. Khoá này được ghim lúc ghép, nên relay
  không tráo được. Associated data gồm Mac, bước, run và project, nên relay
  không đổi được một lệnh `draft` thành `submit`. Mỗi envelope có id và hạn
  6 giờ, và Mac nhớ id đã chạy, nên không gửi lại được. Relay chỉ thấy
  action, run id, project id và ciphertext.
- **Source**: Mac giữ workspace git riêng ở
  `~/AMC/ios-workspaces/<repo>-<hash>`. Lần đầu clone, sau đó fetch rồi
  `checkout --detach` đúng commit, `clean -fd` (giữ file bị ignore như `.env`,
  Pods), và cập nhật submodule. Mỗi release mới đều reset về commit. Các
  bước sau chỉ checkout lại khi workspace đã bị release khác dời đi, để giữ
  đúng trạng thái source hash lúc preflight.
- **File gửi kèm**: chỉ nhận file đã gitignore và không được track, tổng tối
  đa 256 KB, không ghi ra ngoài workspace, không ghi qua symlink.
- **Workflow**: Mac chạy đúng `IosReleaseWorkflowService` như khi build tại
  chỗ (preflight, chốt build number, IPA, upload, processing, App Store).
  Lịch sử lưu riêng trong `ios_build_host/runs`, tách khỏi release của chính
  Mac. Cứ 2 giây Windows nhận snapshot run và 500 dòng log cuối.
- **API key App Store Connect**: lưu trên Windows và gửi mã hoá cùng mỗi
  bước. Mac chỉ giữ trong bộ nhớ trong lúc chạy bước đó; file `.p8` tạm bị
  xoá như luồng cũ.
- **Cấu hình**: lưu trên Windows. Mac bỏ qua Flutter executable của Windows.
  ExportOptions plist phải là đường dẫn tương đối trong project.
- **Điện thoại không nhảy sang Mac**: trước đây `desktop-state` trả về máy
  heartbeat gần nhất. Khi Mac cũng heartbeat, màn hình điện thoại (kể cả nút
  tắt máy) có thể nhảy sang Mac. Giờ relay ưu tiên máy đã ghép điện thoại,
  rồi tới máy `default`, cuối cùng mới tới máy gần nhất.

## Giới hạn

- Chỉ build commit đã push. Thay đổi chưa commit trên Windows không được
  build.
- IPA nằm trên Mac (`ios_build_host/runs/<id>/app.ipa`) và được upload thẳng
  từ đó. Windows không tải IPA về.
- Mỗi máy Windows ghép với một Mac. Muốn đổi Mac thì bỏ ghép rồi ghép lại.
- Khi Mac đang bận build khác, bước mới nằm chờ trong hàng đợi; quá 6 giờ
  thì envelope hết hạn.
- **Dừng** gửi qua relay và Mac dừng tiến trình đang chạy. Upload đã gửi lên
  Apple không hoàn tác được; bấm *Kiểm tra lại Apple* trước khi thử lại.
- Nếu cài lại AMC trên Mac, khoá của Mac đổi. Windows sẽ báo khoá khác lúc
  ghép, phải ghép lại.

## Triển khai relay

Phải deploy relay trước, vì relay cũ không có scope `ios` và endpoint
`/api/mobile/desktops`. `serverless/notifications` là repo git riêng.
Không cần migration D1.

```bash
cd serverless/notifications && npm test && npx wrangler deploy
```

Sau khi deploy, chạy `node worker/verify.mjs <baseUrl> <token>` như các lần
trước.

## Kiểm chứng

- `test/ios_build_envelope_test.dart`: mở đúng envelope; từ chối envelope
  đổi bước, sai Mac hoặc bị sửa.
- `test/ios_build_host_service_test.dart`: git thật với origin local; workflow
  thật với công cụ Apple giả lập. Phủ prepare → TestFlight → App Store, chặn
  gửi lại, hết hạn, commit chưa push, file bị track, workspace sai remote và
  reset phần còn sót của lần build trước.
- `test/remote_ios_build_e2e_test.dart` (tag `e2e`): relay thật qua
  `wrangler dev --local`. Phủ ghép, ghim khoá, prepare và TestFlight qua relay,
  lịch sử và log ở phiên mới. Kiểm tra relay không nhận được key hay nội dung
  file ở dạng rõ, và scope `ios` chỉ tới được đúng Mac.
- Relay: `npm test` (43 test), trong đó có các ca của lệnh `ios` và việc
  chọn máy cho điện thoại. Test e2e cũ của điện thoại vẫn qua.

Chưa kiểm chứng: chạy trên Mac thật với Xcode, codesign và upload thật.
