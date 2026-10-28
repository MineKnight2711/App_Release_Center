# SwiftDesk LAN trong AMC — Phase 1 và 2

Cập nhật 23/10/2026. Có mã core và bản LAN chạy trong AMC, đã build macOS Debug/Release và kiểm thử hai runtime trên cùng Mac. Chưa nghiệm thu giữa hai máy, Windows, input OS khi có Accessibility, hiệu năng hoặc độ bền phiên dài. Không coi bài thử loopback là đủ nghiệm thu Phase 2.

Đây là báo cáo Phase 1/2 tại ngày 23/10. Bản cập nhật ngày 25/10 đã bổ sung Internet/chạy nền/import: xem [Phase 3/4](swiftdesk-phase34.md). Các giới hạn “chưa triển khai” bên dưới mô tả mốc Phase 1/2, không thay cho trạng thái mới.

## Dùng thử trên hai máy

1. Mở **Công cụ dự án → SwiftDesk · Điều khiển máy tính** ở cả hai máy. Host mặc định tắt, không tự mở cổng khi chỉ vào module.
2. Trên máy muốn chia sẻ, cấp Screen Recording (macOS). Cấp Accessibility nếu muốn điều khiển chuột/phím; bản AMC mới có thể cần bật lại theo đường dẫn/chữ ký. Khởi động lại AMC nếu macOS yêu cầu, rồi bấm **Kiểm tra lại quyền**. Máy chỉ xem không cần quyền capture/input.
3. Chọn màn hình, giữ cổng 9877 hoặc chọn cổng phù hợp, bật **Nhận kết nối trên LAN**. Tường lửa phải cho phép AMC trên LAN và WebRTC UDP giữa hai máy.
4. Bấm **Tạo mã ghép nối**, chọn IP LAN đúng nếu có nhiều card mạng/VPN. Chuyển mã tới người điều khiển qua kênh tin cậy. QR chứa cùng mã để chia sẻ; desktop hiện nhận bằng ô dán mã, chưa có camera quét QR.
5. Máy xem dán mã và gửi yêu cầu. Máy chia sẻ kiểm tra tên/IP rồi chấp nhận; mặc định chỉ xem. Chuột/phím và clipboard phải được cấp riêng. Thiết bị đã nhớ vẫn cần chấp nhận mỗi lần, không tự nâng quyền được cấp trước đó.
6. Khi đã nhận frame thật, chọn **Bắt đầu điều khiển**. F12 trả chuột/phím về AMC; mất focus hoặc chuyển sang app khác cũng nhả input. Có gửi văn bản Unicode riêng cho tiếng Việt; phím vật lý phụ thuộc layout/IME máy đích. Có tùy chọn ánh xạ Ctrl/Cmd cho máy Mac.
7. Có chọn màn hình, preset chất lượng, vừa khung/1:1 và mở rộng vùng xem trong app. Clipboard chỉ văn bản tối đa 16 KB, mặc định tắt ở viewer, thao tác gửi/lấy thủ công; không tự đọc liên tục. Không truyền file/ảnh clipboard.
8. Thiết bị đã lưu có sửa tên/IP/cổng và kiểm tra online thủ công; giữ nguyên chứng chỉ đã ghim khi sửa IP. Nếu chứng chỉ thay đổi, ghép lại bằng mã mới. Mục máy được tin cậy trên host cho phép thu hồi credential; thu hồi đóng luôn phiên đang dùng credential đó.

Rời trang trên host giữ listener/phiên trong khi AMC chạy; thanh SwiftDesk ở cuối cửa sổ chính cho phép duyệt chỉ xem, từ chối, mở module và ngắt/tắt host. Rời trang viewer ngắt phiên. Thoát AMC đóng listener, capture, WebRTC và nhả input. Chưa khởi động lại host tự động sau khi thoát, chưa chia sẻ tray/background service với Plan Studio. Nút mở rộng vùng xem không phải chế độ fullscreen của hệ điều hành.

Chạy module riêng, không khởi động account/relay lệnh/Telegram/reminders:

```bash
flutter run -d macos --dart-entrypoint-args=--swiftdesk-lan
# Hoặc chạy executable bản đã build với đối số --swiftdesk-lan.
```

## Các phần đã tích hợp

| Thành phần | Trách nhiệm |
|---|---|
| `packages/amc_remote_core` | Dart thuần: thiết bị, display, phiên, scope, protocol v1, kiểm tra payload, state machine, policy và ports |
| `packages/amc_remote_platform` | Quyền OS, tọa độ display, pointer/button/drag/wheel, HID key, Unicode, nhả phím/nút theo session; Swift và C++ |
| `lib/app/modules/swift_desk/infrastructure` | Chứng chỉ/danh tính LAN, framed TLS transport, host approval, repository, secure adapter và WebRTC engine |
| `services/swift_desk_runtime.dart` | Owner của listener/engine/phiên, deadline, cleanup, recovery, scope, clipboard, thiết bị và lịch sử; UI chỉ subscribe |
| `views` / `widgets` | Ghép nối, xác nhận, màn hình remote, điều khiển có focus, thiết bị đã lưu, trạng thái toàn app |

`connected` cần peer kết nối, cả hai DataChannel mở và xác nhận frame thật từ viewer. Capture lỗi hoặc chỉ có track không được báo đang xem. Mất kết nối nhả input ngay; thử khôi phục tối đa 8 giây, cần hình mới và kênh còn mở. Hết hạn phiên 2 giờ phải kết nối/chấp nhận lại. Heartbeat kênh điều khiển mất hơn 4 giây nhả phím đang giữ. Đây là khôi phục ICE hiện tại; chưa có signaling resume qua đổi mạng.

Hai DataChannel: pointer unordered/maxRetransmits=0; key/button/text/clipboard ordered reliable. Watermark pointer tách khỏi reliable để pointer tới trước không bỏ key-up; button làm cũ pointer trước click. Viewer bỏ pointer đang gom khi click, release hoặc mất focus. Đổi màn hình nhả input và chặn packet mang display cũ. Native chỉ nhận input từ session đã bắt đầu bằng grant còn hiệu lực.

## ADR: signaling LAN và identity

Phase 2 dùng JSON có header độ dài 4 byte trên TLS >=1.2, thay vì thêm WebSocket/server Internet. Chỉ nhận/đi tới private IPv4, loopback và link-local; chưa có discovery mDNS, IPv6 hoặc hostname. Cổng chỉ mở khi người dùng bật host. Video và input vẫn đi qua WebRTC; TLS chỉ chở signaling.

- Mỗi installation có ID ngẫu nhiên, chứng chỉ RSA 2048 tự ký 365 ngày và private key. Mã `amc-lan:1:...` chứa IP/cổng, ID, tên máy, SHA-256 chứng chỉ, token ngẫu nhiên 256 bit và thời hạn 5 phút. Token dùng một lần, bị tiêu thụ trước khi đợi người nhận chấp nhận; từ chối cần mã mới.
- Viewer kiểm tra pin và thời hạn chứng chỉ trước khi gửi credential. Không tin CA hệ thống thay cho pin, không chấp nhận chứng chỉ bất kỳ. Ghim TLS cũng bảo vệ SDP fingerprint WebRTC; peer WebRTC dùng DTLS.
- Có yêu cầu ALPN `amc-remote/1`; Dart TLS trên Mac kiểm thử trả về null dù đã cấu hình. Cho phép null, từ chối giá trị khác; pin TLS và version `v1` của mọi message luôn bắt buộc. Không dùng ALPN thay cho xác thực.
- Host giữ hash SHA-256 của remembered token, giới hạn scope theo lần cấp trước. Viewer giữ token gốc qua `RemoteCredentialStore`. Host vẫn đợi con người duyệt tối đa 60 giây. Một phiên hoạt động mỗi runtime; không có mật khẩu chung hoặc unattended.
- Giới hạn frame 256 KiB trước cấp phát, SDP 192 KiB, partial frame/auth timeout 8 giây, sequence liên tiếp theo session, heartbeat signaling 10 giây và đóng khi im lặng 35 giây. Host tối đa 4 kết nối chờ, 6 lần/phút/IP. Một lời mời chỉ dành cho một người xin tại một thời điểm.
- Chứng chỉ hết hạn làm runtime báo lỗi và yêu cầu tạo lại danh tính/ghép lại; chưa tự luân chuyển identity hoặc đồng bộ identity qua máy khác. Internet enrollment giữ fingerprint bất biến, nên đổi chứng chỉ cần identity mới và thu hồi bản enrollment cũ.

Metadata có version trong `<AppSupport>/swift_desk/devices.json`: thiết bị, controller hash/scope, tối đa 50 lịch sử kết thúc phiên. Ghi có hàng đợi, file tạm/rename và rollback bộ nhớ khi ghi thất bại; lỗi dữ liệu hiện rõ thay vì âm thầm xóa. Không lưu credential thô, SDP, clipboard hoặc frame trong metadata/lịch sử.

Token và cert/private key dùng adapter `SecureKeyValueStore` sẵn của AMC với prefix `swift_desk.v1.`. Trên macOS đây là file mã hóa gắn hardware UUID theo cơ chế AMC hiện có, không phải keychain phần cứng; Windows theo backend secure storage hiện có. Không thêm password plaintext hoặc tự thay policy lưu secret của AMC. Unattended cần đánh giá lại kho khóa trước khi thiết kế Phase 3/4.

Engine ứng viên hiện tại `flutter_webrtc` được giữ pin như spike. Đã tiếp tục xây core/LAN theo yêu cầu người dùng sau khi capture/DataChannel cục bộ chạy được; quyết định này chưa đóng gate kiểm thử Windows, native input thật và TURN của Phase 0.

Native Windows ánh xạ screen ID qua chỉ số `EnumDisplayDevicesW` rồi tên monitor, đối chiếu với [WebRTC screen capture utils](https://webrtc.googlesource.com/src/+/refs/heads/main/modules/desktop_capture/win/screen_capture_utils.cc); libwebrtc lấy danh sách ID từ capturer trong [media list implementation](https://github.com/webrtc-sdk/libwebrtc/blob/main/src/rtc_desktop_media_list_impl.cc). Đây là đối chiếu source, vẫn cần xác nhận mapping trên binary Windows đã pin và nhiều màn hình thật.

## Kiểm chứng ngày 23/10/2026

- macOS Debug và Release build thành công. Core Dart phân tích độc lập không có issue; phân tích root chỉ còn 3 issue sẵn có ở release-note/Telegram/safe-scan.
- Nhóm SwiftDesk cuối cùng: **37 test pass**. Kiểm tra policy/state/expiry/replay, schema, storage rollback, TLS pin và approval, token hash/revoke, runtime/frame gate/display fence, native cleanup với fake, permission denial, UI/scope/theme, mất focus, pointer batching và thu hồi clipboard trong lúc đọc nội dung.
- Full suite tại thời điểm chạy: 971 pass, 16 skip, 25 fail. Đã chạy 5 file lỗi trên snapshot `HEAD` riêng không chứa SwiftDesk; tái hiện đúng cùng 25 tên test lỗi: 5 Windows autostart, 10 machine power, 6 remote power, 3 QA integration dùng đường dẫn Windows và 1 QA HTTPS fixture. Không sửa các lỗi ngoài phạm vi này. Hai test surface và một test clipboard bổ sung sau full suite đều được chạy trong nhóm SwiftDesk cuối cùng.
- Release smoke: hai runtime độc lập, identity tạm, file metadata tạm, TLS ghim chứng chỉ thật, approval, WebRTC video thật và hai DataChannel. Ba vòng: ghép mới, nhớ máy, nhớ máy + đổi chất lượng. Cả ba đều nhận frame, nhận packet trên hai kênh, chặn OS input ở view-only, cleanup và giữ listener. Thu hồi remembered credential rồi kết nối lại bị từ chối trước approval.
- Smoke chỉ bind loopback, không dùng kho dữ liệu production, không tự cấp quyền, không tiêm input OS. UI cũng được xem trực tiếp bằng bản preview bundle riêng, host tắt/không có quyền.
- Bằng chứng: [Release LAN](evidence/swiftdesk-lan-phase12-macos-2026-10-23.json), [kiểm tra hồi quy](evidence/swiftdesk-phase12-validation-2026-10-23.json), [spike trước đó](evidence/swiftdesk-macos-loopback-2026-10-23.json).

Chạy lại nhóm SwiftDesk và smoke:

```bash
flutter test test/swift_desk_protocol_test.dart test/swift_desk_session_test.dart \
  test/swift_desk_lan_test.dart test/swift_desk_runtime_test.dart \
  test/swift_desk_view_test.dart test/swift_desk_lifecycle_test.dart \
  test/swift_desk_probe_view_test.dart
flutter build macos --release
'build/macos/Build/Products/Release/App Management Center.app/Contents/MacOS/App Management Center' \
  --swiftdesk-lan-smoke-report=/tmp/amc-lan-report.json
```

## Còn nghiệm thu trước khi phát hành LAN

| Hạng mục | Trạng thái |
|---|---|
| Mac loopback Release, TLS/video/DataChannel/remember/revoke | Đã qua 3 vòng; không thay cho hai máy |
| Accessibility và thao tác OS thật | Người dùng sẽ tự cấp; binary Release vừa thử vẫn báo input=false; chưa thử click/phím/Unicode thật |
| Windows build và Win↔Win / Mac↔Mac / Win↔Mac hai chiều | Chưa có máy đối ứng trong phiên làm việc; C++ có mã nhưng chưa compile trên Windows |
| Nhiều display, Retina/DPI hỗn hợp, IME tiếng Việt, drag/scroll/shortcut | Có mã và fake test; cần phần cứng/IME thật |
| Clipboard, focus loss, khóa máy/UAC, mất mạng, sleep/resume | Có policy và test phần mềm; cần QA hai máy, xác nhận desktop đặc quyền bị từ chối |
| 60 phút, 20 reconnect, CPU/RAM, latency p50/p95, FPS màn hình động | Chưa đo; thống kê trên màn hình tĩnh không phải kết quả hiệu năng |
| Internet ID/WSS/TURN, unattended, installer/tray/autostart/import | Phase 3/4, chưa triển khai trong đợt này |

Windows input giới hạn user desktop hiện tại và mức integrity của AMC; không điều khiển UAC/secure desktop hoặc app nâng quyền. macOS chỉ phiên người dùng hiện tại; không điều khiển loginwindow. Không mở port router hay tự đổi tường lửa/quyền hệ thống.
