# SwiftDesk trong AMC — ghép bằng mã máy

Cập nhật 02/11/2026. Luồng mặc định không cần tài khoản AMC hoặc tự triển khai máy chủ. Phần API tài khoản/TURN của Phase 3/4 vẫn được giữ trong **Cài đặt nâng cao · Máy chủ AMC và chạy nền**.

## Cách dùng

1. Cài cùng bản AMC mới trên cả hai máy. Mở **SwiftDesk · Điều khiển máy tính** từ Công cụ dự án hoặc tìm bằng ⌘K/Ctrl+K. Chưa đăng nhập thì dùng nút **Mở SwiftDesk · Không cần đăng nhập** ngay màn hình đăng nhập.
2. Máy được điều khiển: cấp Screen Recording khi cần chia sẻ màn hình, rồi bấm **Cho phép kết nối bằng mã**. macOS chỉ cần Accessibility nếu muốn nhận chuột/phím.
3. **Mã máy này** có 9 số, giữ ổn định theo danh tính cài đặt. **Mật khẩu ghép tạm thời** có 16 ký tự, ngẫu nhiên 96 bit, tối đa 5 phút và dùng một lần. Bấm **Sao chép mã kết nối** rồi gửi riêng cho máy đối tác.
4. Máy điều khiển: dán vào **Mã máy đối tác hoặc mã kết nối** rồi bấm **Kết nối bằng mã**. Có thể nhập ID 9 số và mật khẩu ở hai ô riêng. Máy điều khiển không cần quyền capture/Accessibility để gửi yêu cầu xem.
5. Máy đích chấp nhận từng phiên, chọn view/input/clipboard như trước. Không có tự chấp nhận trong luồng dùng thật. F12 trả điều khiển về AMC.
6. Nếu chọn nhớ máy, lần sau nhập ID hoặc bấm máy đã nhớ, không cần mật khẩu tạm nhưng vẫn cần host chấp nhận. Thu hồi quyền trên máy đích sẽ chặn credential cũ.

Mã này dùng giữa hai bản **AMC**, không dùng ID/mật khẩu hoặc wire protocol của ứng dụng Electron SwiftDesk cũ. LAN/QR và dữ liệu máy đã ghép cũ được giữ. Import cấu hình SwiftDesk cũ vẫn chỉ lấy metadata và yêu cầu ghép lại.

## P2P và máy chủ tùy chọn

- **Tự động · P2P IPv6/IPv4** dùng STUN công cộng và ICE trực tiếp. Có đường IPv6 thì có thể chọn IPv6 như SwiftDesk gốc; stats hiển thị loại đường thật.
- **Chỉ P2P IPv6** giữ bộ lọc candidate IPv6 hai chiều và kiểm selected pair trước connected. Không tự chuyển IPv4/TURN khi thiếu IPv6.
- **Bắt buộc TURN** thuộc luồng máy chủ AMC riêng, cần TURN đã cấu hình; luồng ghép mã công cộng sẽ báo rõ thay vì tự hạ chế độ.

Broker công cộng chỉ giúp hai máy gặp nhau và chuyển signaling mã hóa. Không có frame/input/clipboard đi qua MQTT. Mạng chặn UDP/P2P hoặc không có IPv6 khả dụng có thể cần TURN riêng; không bảo đảm kết nối được mọi mạng chỉ bằng STUN. Broker công cộng có thể mất kết nối; đây không phải hạ tầng do AMC vận hành.

**Giữ host khi đóng cửa sổ**, **Khôi phục host khi mở AMC** và **Khôi phục nhận bằng mã** trong phần nâng cao là các lựa chọn riêng. Khôi phục nhận bằng mã không cần tài khoản; khôi phục máy chủ AMC riêng vẫn cần tài khoản/cấu hình API. Phiên Internet hiện giới hạn 15 phút, sau đó cần kết nối/chấp nhận lại.

## Cơ chế ghép nối

- Dùng `mqtt_client` qua TLS EMQX (WSS dự phòng) và WSS HiveMQ, cùng các nhà cung cấp broker mà SwiftDesk gốc sử dụng. Kết nối các cluster khả dụng để tránh hai máy vô tình chọn hai broker khác nhau. TLS kiểm chứng chứng chỉ bình thường, không có bypass.
- Namespace riêng `amc/swiftdesk/v1`. Host chỉ đăng ký nhận khi người dùng bật chia sẻ. Không cần API AMC/enrollment/account token. Không publish retained hoặc giữ phiên MQTT lâu dài; chỉ subscribe topic host của chính mình và topic ngẫu nhiên của phiên.
- Client/host tạo khóa X25519 tạm. Hello có HMAC từ mật khẩu hoặc hash trust token; host kiểm trước khi cấp slot/timer hoặc tạo khóa/ký challenge, nên chỉ biết ID không đủ chiếm slot ghép. HMAC-SHA256 tiếp tục xác thực transcript gồm ID, UUID viewer, chế độ known, session UUID, hai nonce, hai public key, UUID và fingerprint host. Host còn ký RSA-SHA256 transcript bằng danh tính hiện có; viewer kiểm chữ ký và pin đã lưu để hash token bị lộ không đủ giả danh host.
- HKDF-SHA256 kết hợp shared secret X25519, hash transcript và secret xác thực. Signaling dùng lại hai khóa AES-256-GCM theo chiều/session của `CloudSignalingTransport`. Bootstrap chứa pair token cũng được mã hóa, trước khi runtime/LAN policy duyệt request. Broker không nhận mật khẩu, raw trust token, hostname, SDP hoặc nội dung desktop dạng rõ.
- Envelope có HMAC và sequence riêng để loại giả mạo, duplicate từ hai cluster, replay cũ, và giữ hàng đợi reorder tối đa 32 packet. RemoteSignal tiếp tục có session/sequence/AAD riêng. Packet tối đa 400 KB, hàng đợi xử lý tối đa 64, tối đa 4 handshake và 12 lần tạo challenge/phút, timeout handshake 25 giây.
- Password hết hạn/đổi/đã dùng không tạo được yêu cầu phê duyệt. Sau proof hợp lệ, mới tạo pair token và xoay password. Credential đã nhớ vẫn đi qua hash/scope/revoke và phê duyệt hiện có; handshake không cấp input. Input chỉ mở sau hình thật và cả hai DataChannel.
- Runtime có registry service để đường ghép công cộng và backend riêng không ghi đè callback hoặc làm mất cleanup của nhau. Khi quit, từng service được drain; lỗi một service không ngăn các service khác đóng.

## Kiểm tra lại

Kết quả bản ngày 02/11/2026 nằm trong [bằng chứng xác nhận](evidence/swiftdesk-public-id-validation-2026-11-02.json) và [báo cáo nhận hình qua broker thật](evidence/swiftdesk-public-id-macos-2026-11-02.json):

| Kiểm tra | Kết quả |
|---|---|
| SwiftDesk, auth, Plan Studio/reminder/settings | 100 test đạt; gồm 12 test mới cho ghép mã và 2 test UI mới |
| Phân tích mã | Core không có vấn đề; root còn 3 cảnh báo/thông tin cũ, không có vấn đề mới |
| Broker công cộng | Publish/subscribe thật đạt, không dùng dữ liệu cá nhân |
| Tự động | 3/3 phiên: ghép mới, máy đã nhớ, kết nối lại; stats cả hai đầu là P2P IPv6 |
| Chỉ P2P IPv6 | 3/3 phiên với frame thật và cả hai DataChannel; thu hồi chặn credential cũ |
| macOS UI | Đã xem trực tiếp mã máy, ô ID/mật khẩu và nút kết nối ở đầu trang trong bundle preview riêng; host giữ tắt |
| Release/DMG | Universal x86_64/arm64; kiểm chữ ký, checksum, mount chỉ đọc; executable/Dart AOT trong DMG trùng bản Release đã thử |

Các phiên thử dùng hai endpoint tạm trên một Mac, signaling đi qua broker công cộng thật; không dùng tài khoản AMC/Worker và không tiêm OS input. Chưa đo hiệu năng liên tục hoặc kiểm hai ISP khác nhau. Không chạy lại toàn bộ test root trong đợt này; kết quả 100 test là bộ hồi quy liên quan.

Lần thử Tự động đầu tiên từng dừng vì đợi STUN không tới được dù có candidate trực tiếp. Engine nay có thể trao đổi SDP đã thu thập sau 5 giây khi có candidate thật, không đợi mãi mọi STUN server; nếu vẫn không có candidate, timeout 12 giây được giữ. Hai chế độ đều qua đủ ba phiên trên bản cuối sau sửa này.

`dart run tool/swiftdesk_public_broker_smoke.dart` dùng topic ngẫu nhiên và payload thử, không truy cập danh tính, account hoặc desktop của người dùng.

Sau build macOS Release và kiểm tra chữ ký app, có thể chạy harness disposable bằng `--swiftdesk-public-smoke-report=/tmp/amc-public-smoke.json`; thêm `--swiftdesk-public-smoke-mode=directIpv6` để bắt buộc kiểm đường IPv6. Harness tạo hai runtime/danh tính tạm, chỉ tự chấp nhận view-only của chính hai endpoint thử và không tiêm OS input. Không dùng cờ smoke cho app đang chia sẻ thật.

Kiểm thử hai mạng/ISP và Windows, input/IME/DPI thật, sleep/lock, 60 phút soak, login item và bộ cài đã ký vẫn là gate nghiệm thu phần cứng. Hướng dẫn API/TURN cũ ở [Phase 3/4](swiftdesk-phase34.md) mô tả đường máy chủ riêng, không phải điều kiện để dùng ghép mã mặc định.

Tham khảo API MQTT từ [mã nguồn chính thức mqtt_client](https://github.com/shamblett/mqtt_client) và [ví dụ kết nối server](https://github.com/shamblett/mqtt_client/blob/master/example/mqtt_server_client.dart); implementation và bằng chứng AMC nằm trong repo này.
