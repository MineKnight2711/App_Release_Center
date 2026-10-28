# SwiftDesk — thử engine trong AMC

Ngày thực hiện: 23/10/2026. Trạng thái ADR: **tạm chọn Flutter WebRTC để thử; chưa chốt engine production**.

## Đã có trong source

- Trang **Công cụ dự án → SwiftDesk · Thử kết nối**, tìm được bằng command palette.
- Chế độ độc lập `--swiftdesk-spike`, vào trang thử trước `AppBinding`: không khởi động account/session của AMC, relay lệnh, Telegram hay Plan Studio. Không mở thêm bản AMC bình thường để thử cùng app đang chạy nhận lệnh thật.
- Capture một display được chọn (ràng buộc `deviceId.exact`), stream video không audio qua hai peer WebRTC và render bằng texture. Không gửi frame thô qua MethodChannel.
- Thử loopback trên một máy; tạo host offer, viewer answer và nhập trả lời bằng mã JSON thủ công để thử hai máy. Code chưa đăng ký ID, không có signaling server hay listener socket nhận lệnh ngoài mạng.
- TURN được nhập thủ công, giữ trong bộ nhớ trang; `relay` policy để ép đường relay. Chưa có server TURN mặc định hoặc credential production.
- Một DataChannel reliable để ping và thử pointer/Unicode. Chưa có full key/button/scroll, clipboard, nhiều màn hình đồng thời, file transfer hay audio. Chưa dùng kênh unordered vì cần kiểm chứng riêng cách plugin serialize `maxRetransmits = 0`.
- Core Dart riêng kiểm payload, version, sequence, session ID, expiry và grant mặc định tắt. Native kiểm thêm session/display và quyền OS. Tắt input, mất kết nối hoặc đóng trang sẽ thu hồi input. `endInput` ràng buộc session để một trang không thu hồi nhầm phiên khác.
- Timeout khi không nhận frame thật; guard khi đóng trang trong lúc khởi tạo; đóng peer/channel/track/texture khi dừng.

Đây là spike để kiểm engine, không phải bản remote desktop phát hành. Ghép nối production, định danh peer, scope account/team và unattended chưa có. Mã phiên thủ công phải được chuyển qua kênh tin cậy cho đúng máy; không dùng nó như ID công khai. Mã chứa SDP/ICE/fingerprint, hết hạn sau 10 phút và không được ghi vào báo cáo.

## Kết quả xác minh

Môi trường: Flutter 3.47.6 / Dart 3.13.5, Xcode 27.1, macOS 27.0.1. Pin `flutter_webrtc: 1.6.2+hotfix.4`; macOS dùng Swift Package Manager với WebRTC SDK 150.7871.01. macOS deployment target của AMC vẫn là 12.0.

| Hạng mục | Kết quả |
|---|---|
| SwiftDesk source hiện có | `npm run build` qua |
| AMC baseline | macOS debug build qua |
| AMC với module thử | macOS debug và release build qua; release universal arm64/x86_64, native Swift plugin compile/link được |
| Capture → WebRTC → texture | Đã nhận frame thật trên macOS với display được chọn |
| Lặp mở–dừng | 3/3 vòng nhận frame + phản hồi DataChannel; capture được dừng, session reference được giải phóng |
| Input chưa có grant | Native trả lỗi `session`, không gửi sự kiện vào OS |
| Giao diện native | Đã mở trang thử; trạng thái thiếu quyền và thông báo mã không hợp lệ hiển thị; không tự xin quyền |
| Test mới | 10 ca qua: protocol/expiry/replay/bounds/Unicode, permission UI, vòng đời khởi tạo/đóng và grant trước kết nối |
| Regression chọn lọc | Lượt cuối 122 ca qua, 10 bỏ qua theo môi trường, gồm toàn bộ 10 test SwiftDesk |
| Phân tích source | Vẫn 3 cảnh báo có sẵn, không phát sinh cảnh báo ở phần mới |

Bản release được build tại `build/macos/Build/Products/Release/App Management Center.app`.
Đây là bản build cục bộ; chưa tạo installer/notarize hay thay thế bản AMC đang cài.
Đã chạy 3 vòng trên chính bản release này; [báo cáo gốc](evidence/swiftdesk-macos-loopback-2026-10-23.json)
ghi frame/byte nhận được, phản hồi DataChannel, trạng thái giải phóng phiên và input bị từ chối khi chưa có grant.

Không coi kết quả loopback là bằng chứng hiệu năng LAN/Internet. Frame counter tăng ít khi màn hình đứng yên; cần nội dung chuyển động, đo frame age/input-to-visible latency và CPU/RAM trong lượt thử riêng. Ba vòng không chứng minh không có memory leak dài hạn; ma trận 60 phút/20 reconnect trong plan vẫn còn.

Baseline có 6 lỗi trong nhóm `remote_control_power_test.dart`: service kiểm tra khả năng điều khiển nguồn của OS trong khi test dựng lệnh Windows trên macOS. Nhóm này lỗi trước khi thêm SwiftDesk. Phân tích baseline có hai cảnh báo `unawaited_return_in_try_block` ở release note/Telegram và một lint nối chuỗi ở `safe_scan_test.dart`.

Thay đổi macOS Podfile/Podfile.lock/project.pbxproj đã tồn tại khi bắt đầu công việc; không reset chúng. Các file đăng ký plugin được cập nhật theo dependency mới. Không chép nguyên code Electron hoặc config chứa secret từ SwiftDesk vào AMC; repo SwiftDesk hiện ghi MIT trong package nhưng không thấy file LICENSE ở root, vẫn cần xác minh khi port phần source cũ.

## Cách chạy

Trong repo AMC, build ứng dụng mới. Bản đang cài cũ chưa có entry SwiftDesk.

macOS:

```sh
flutter pub get
flutter build macos --debug
open -n "build/macos/Build/Products/Debug/App Management Center.app" --args --swiftdesk-spike
```

Nếu có nhiều bản AMC cùng bundle ID đang chạy, hệ điều hành/công cụ UI có thể chọn nhầm cửa sổ. Dùng đúng cửa sổ có tiêu đề trong trang là **SwiftDesk · Thử kết nối**; tránh thao tác vào cửa sổ AMC đang chạy công việc thật.

Windows (chưa xác minh trên máy Windows):

```powershell
flutter pub get
flutter build windows
& '.\build\windows\x64\runner\Release\app_management_center.exe' --swiftdesk-spike
```

### Thử trên một máy

1. Kiểm tra quyền. Trên macOS, host cần Screen Recording; để thử native input cần thêm Accessibility. Bấm **Cấp quyền trên máy này** rồi làm theo OS, sau đó **Kiểm tra lại quyền** hoặc mở lại app khi OS yêu cầu. Không cần camera/microphone cho thử này.
2. Chọn display, bấm **Thử trên máy này**. Chỉ kết luận media hoạt động khi có hình và counter frame giải mã tăng; RTT kênh dữ liệu không phải độ trễ thao tác.
3. Nếu muốn thử native: mở phần **Thử chuột và nhập tiếng Việt**, bật cho phép input trên host, đặt focus ở ô nhận chữ, gửi chữ thử hoặc di chuyển chuột tới giữa màn hình host. Input phải mặc định tắt sau khi dừng.
4. Dừng, thử lại, rồi đóng trang. Không có capture tiếp tục chạy sau khi trang đóng.

Native Windows chỉ nhắm desktop đang đăng nhập; không coi cờ permission là bảo đảm vượt qua UIPI/UAC. Không có click, key hold hay tổ hợp đăng nhập hệ thống ở spike này.

### Thử hai máy

1. Cả hai mở chế độ riêng. Host chọn màn hình → **Tạo phiên chia sẻ cho máy khác**.
2. Host mở **Kết nối hai máy bằng mã phiên** → **Sao chép mã mời**, chuyển cho viewer qua kênh tin cậy.
3. Viewer dán mã → **Nhận mã mời (viewer)** → gửi mã trả lời lại host.
4. Host dán trả lời → **Hoàn tất trên host**. Viewer phải thấy hình và counter frame tăng.
5. Host bật quyền input riêng nếu muốn thử. Focus trường nhận chữ ở host, sau đó viewer gửi chữ thử. Máy viewer không cần quyền ghi màn hình để xem.
6. Đổi vai, chạy lại; thử dừng host/viewer, mất mạng, từ chối/thu hồi permission và display DPI khác nhau.

Mặc định không có STUN công cộng: bắt đầu với LAN. Muốn thử khác mạng, nhập TURN URL (`turn:`/`turns:`), tài khoản và credential thử ở cả hai máy, bật **Bắt buộc đi qua TURN** trước khi tạo offer/answer. Kiểm tra ICE candidate `relay` và log phía TURN; không kết luận force-TURN thành công chỉ vì UI đã connected. Không đưa credential vào báo cáo hoặc commit.

### Kiểm tra tự động trên bản app macOS

Chế độ sau không tự xin permission hay gửi input vào OS. Nếu chưa có quyền screen recording thì báo `blocked` thay vì tự cấp quyền. Nó chạy 3 vòng capture loopback, đợi frame, kiểm DataChannel và dừng, ghi báo cáo không có SDP/credential rồi thoát. `sessionReleased` kiểm tra tham chiếu phiên/input đã đóng, không phải số đo bộ nhớ.

```sh
"build/macos/Build/Products/Debug/App Management Center.app/Contents/MacOS/App Management Center" \
  --swiftdesk-spike --swiftdesk-smoke-report=/tmp/amc-swiftdesk-smoke.json
```

## Còn thiếu để kết thúc Phase 0

- [ ] Build và chạy trên Windows thật, xác minh ABI/download native SDK.
- [ ] Capture/input Win↔Mac hai chiều và Mac↔Mac/Win↔Win; kiểm display mapping, Retina/DPI, Unicode thực tế.
- [ ] Cấp Accessibility cho bản AMC thử và chứng minh chữ/chuột thực sự tới OS. Hiện máy Mac trả `inputPermission: false`; mới xác minh nhánh từ chối.
- [ ] Force-TURN với hạ tầng và credential thử, kiểm relay/UDP/TLS 443.
- [ ] Đo hiệu năng khi màn hình chuyển động và chạy lâu/reconnect đủ ma trận.
- [ ] Chốt ADR engine, protocol/pairing và lộ trình native fallback dựa trên kết quả hai OS.

Sau các điều kiện này mới hoàn thiện API core production, safe pairing LAN và runtime dùng chung ở Phase 1–2. Phần tray/autostart, ID/signaling backend, stored device migration và Android viewer chưa triển khai trong spike này.

Nguồn đối chiếu: [Flutter WebRTC](https://github.com/flutter-webrtc/flutter-webrtc), [MediaDevices](https://flutter-webrtc.org/docs/flutter-webrtc/api-docs/media-devices/), [SendInput/UIPI](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput). Mapping source Windows dựa vào [WebRTC GetScreenList](https://webrtc.googlesource.com/src/+/refs/heads/main/modules/desktop_capture/win/screen_capture_utils.cc), vẫn cần thử với SDK đã pin và nhiều màn hình.
