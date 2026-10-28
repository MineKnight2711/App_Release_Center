# SwiftDesk — cập nhật upstream, Phase 3 và 4

Cập nhật 26/10/2026. Đã triển khai Internet desktop và nền chạy chung trong AMC, kiểm thử với Worker cục bộ và macOS. Chưa triển khai lên Cloudflare production, chưa có TURN thật hoặc ma trận hai máy Windows/macOS. Theo lựa chọn của người dùng, đợt này chuẩn bị TURN mẫu và kiểm thử cục bộ.

## Đối chiếu SwiftDesk mới nhất

Đã fetch lại `origin/main` ngày 26/10/2026 của `/Users/witherdragon/Work/source/window_mac/amc_remote`. Checkout nguồn giữ nguyên `32ae86a`; remote mới nhất vẫn `53ba594`, chỉ thêm `docs/SETUP.md`. Đọc cả code ở checkout và tài liệu trên remote; không sửa dữ liệu hay cài helper của SwiftDesk gốc.

| Thay đổi upstream | Quyết định trong AMC |
|---|---|
| Ctrl trái → Command, Ctrl phải giữ Control, không đổi mapping khi viewer là Mac | Đã sửa mapping của viewer AMC; nhả input khi đổi lựa chọn |
| Clipboard mới nhất trước khi paste, tránh V tới trước clipboard | Thêm tùy chọn riêng, mặc định tắt; cần scope clipboard. Viewer đợi ACK sau khi OS máy đích áp dụng clipboard rồi mới gửi V. Quá 2 giây/hết quyền thì bỏ paste |
| Nhả modifier, double-click, viewer mất focus | Giữ cleanup native đã có; bổ sung chung vào đường Internet. Mất focus/F12 vẫn trả điều khiển |
| Chạy nền, một entry autostart, phục hồi host | Một tray/menu bar do AMC quản lý; reason riêng cho reminders và remote; khôi phục host/Internet opt-in; Windows dùng lại shortcut startup AMC, macOS dùng SMAppService |
| Lần mở thứ hai không khởi tạo dịch vụ | Windows đã có mutex; thêm chặn instance Release macOS trước tạo Flutter engine. Chế độ chẩn đoán có đối số riêng vẫn được chạy độc lập |
| Cloud ID/MQTT broker công cộng, password và JPEG relay | Dùng API tài khoản AMC, ID server cấp, vé một lần, WSS và signaling mã hóa tới host; không nối public MQTT hoặc chở frame qua API |
| P2P IPv6 tự động, thống kê đường IPv6/IPv4/TURN, tránh hết slot IPv6 do VPN | Giữ ICE IPv6 trong chế độ tự động; thêm chọn chỉ IPv6 hoặc TURN; tăng giới hạn mạng IPv6 lên 32 qua API plugin đã ghim, thay vì gọi policy riêng của Electron |
| Root helper/loginwindow | Chưa port/cài. Phạm vi hiện tại là user desktop; UAC, secure desktop, màn hình đăng nhập và unattended vẫn ngoài bản này |
| Global keyboard hook Windows, con trỏ dot, custom resolution/VP9 | Chưa port toàn bộ. Giữ phím Flutter/HID, ô Unicode, chọn display/preset/1:1 hiện có; cần nghiệm thu Windows và hiệu năng trước khi thay engine/capture hook |

## Phase 3 — đường Internet

Trong **SwiftDesk → Internet · Tài khoản AMC**, đăng nhập AMC, bật host LAN trên máy chia sẻ rồi **Bật nhận Internet**. Host LAN và Internet dùng cùng policy, chỉ một phiên hoạt động; chưa tách chế độ host chỉ Internet. Có ID AMC 12 chữ số, tạo mã Internet 5 phút dùng một lần, kết nối bằng mã và danh sách máy Internet đã nhớ. Mỗi kết nối lại đều cần host chấp nhận. ID AMC là namespace mới, không dùng ID của SwiftDesk cũ.

Backend tại `cloudflare/amc-api` bổ sung:

- Migration `0003_desktop.sql`: installation ID, chủ tài khoản, cloud ID, fingerprint chứng chỉ, tên/platform và trạng thái thu hồi. Một tài khoản tối đa 20 installation đang hoạt động. Enrollment không cho tài khoản khác chiếm ID hoặc thay fingerprint của ID đã đăng ký.
- Durable Object `DesktopRoom` riêng mỗi host. Host mở WSS sau khi xác thực tài khoản AMC. Viewer cần installation đã enroll và lời mời hợp lệ hoặc ACL đã được host ghi nhớ; nhận ticket ngẫu nhiên 256 bit, 30 giây, dùng một lần, gắn owner/installation/fingerprint.
- Lời mời backend được hash, dùng một lần trước ticket; đây là code khác pair token của host. ACL chỉ ghi sau callback approval ở host. Backend ACL không thay thế kiểm tra token hash/scope và phê duyệt tại AMC host.
- WSS dùng Authorization header, ticket trong header riêng; không đặt bearer/ticket vào URL. Server chỉ chuyển envelope ciphertext tới session của ticket, không lưu SDP, input, clipboard, frame hoặc remembered token thô. Chặn binary, packet/HTTP body quá lớn, phiên chéo, quota ticket/socket và rate limit.
- TURN REST credential HMAC-SHA1 có thời hạn 15 phút, gắn session ID. Secret dài hạn chỉ nằm ở API/coturn. Phiên Internet cũng tối đa 15 phút, rồi phải kết nối/chấp nhận lại. Chưa có refresh TURN/resume dài hạn cho phiên cũ.
- Host có reconnect signaling với backoff 3–30 giây; phiên media hiện tại kết thúc khi mất room, không tự chấp nhận lại. Hủy/đổi tài khoản trong app đóng Internet sau lần kiểm tra token tiếp theo (10 giây); room kiểm tra session/revoke trên server mỗi phút. LAN không phụ thuộc đăng nhập Internet.
- Thu hồi controller ở host luôn thực hiện local trước, kể cả khi API lỗi. Backend có revoke/disable để xóa ACL/ticket và đóng socket; nếu API tạm mất, host vẫn chặn credential đã xóa ở kết nối kế tiếp.

Mã hóa signaling: lời mời chứa cert host và fingerprint SHA-256. Viewer kiểm pin/thời hạn, dùng RSA-OAEP-SHA256 bọc secret AES ngẫu nhiên; HKDF-SHA256 sinh hai khóa theo chiều/session; mỗi packet dùng AES-256-GCM, nonce riêng, AAD session/sequence và sequence liên tiếp. Backend biết metadata định tuyến và thời gian, không giải mã được pair token/remembered token/SDP. WebRTC vẫn mã hóa media/input bằng DTLS/SRTP. URL API trong lời mời phải trùng API AMC đang cấu hình, không tự gửi token tài khoản sang server khác.

UI có **Đường kết nối Internet**, chọn trước khi mở phiên:

- **Tự động · P2P IPv6/IPv4, TURN dự phòng** (mặc định): giữ cả candidate IPv6/IPv4 và ICE server do API cấu hình. WebRTC chọn đường khả dụng; không ép mọi phiên qua TURN và không cam kết luôn chọn IPv6 khi IPv4 cũng tốt.
- **Chỉ P2P IPv6 · Không qua TURN**: không dùng STUN/TURN server, chỉ trao đổi và nhận candidate IPv6 unicast không phải relay, lọc cả SDP gửi và nhận. IPv4-mapped IPv6 và mDNS chưa xác định được IPv6 không được xem là candidate IPv6. Thiếu candidate IPv6 thì báo lỗi, không tự chuyển sang IPv4/TURN. Engine chỉ xác nhận connected sau khi stats của candidate pair đã chọn chứng minh P2P IPv6; vẫn cần frame thật và cả hai DataChannel trước khi runtime cấp input.
- **Bắt buộc TURN**: giữ đường kiểm thử relay; thiếu TURN thì báo lỗi, không tự fallback khi đã yêu cầu relay.

Lựa chọn được lưu dưới `swift_desk.connectionMode`; cài đặt `forceRelay=true` cũ vẫn được đọc nếu chưa có lựa chọn mới. Áp dụng cho phiên Internet mới, khóa thay đổi khi đang kết nối/có phiên. Ý định kết nối của viewer đi trong signaling mã hóa, host tự động sẽ tôn trọng yêu cầu IPv6/TURN bắt buộc; nếu hai đầu chọn hai chế độ bắt buộc khác nhau, từ chối trước khi cấp quyền. Máy đã nhớ và cờ khôi phục host/Internet dùng lại lựa chọn này, không tự hạ xuống chế độ khác.

Thống kê lấy candidate pair thật, hiện `P2P IPv6`, `P2P IPv4`, `TURN relay` hoặc đường chưa xác định; TURN dùng địa chỉ IPv6 vẫn được ghi là relay. Không lưu IP trong diagnostics và không suy ra loại đường truyền từ ping. IPv6 P2P dùng API AMC để xác thực/ghép máy nhưng hình ảnh và điều khiển đi trực tiếp giữa hai máy; không cần TURN nếu IPv6 thực tế liên lạc được. Firewall hai đầu vẫn phải cho phép lưu lượng WebRTC. Với cấu hình chưa có STUN/TURN, bài thử loopback vẫn chạy được, không suy ra kết nối vượt NAT sẽ hoạt động. Listener/mã LAN Phase 1/2 hiện vẫn dành cho IPv4 nội bộ; tùy chọn mới điều khiển đường media của kết nối Internet qua API.

## Phase 4 — vòng đời và dữ liệu

`AppBackgroundService` sở hữu native channel `amc/background`, tập reason và callback shutdown. Plan Studio dùng reason `reminders`; SwiftDesk dùng `remoteHost` khi có phiên hoặc host bật tùy chọn chạy nền. Tắt reason reminders giữ tray nếu remote còn cần. Một owner không được tự tắt tray của owner khác.

macOS có NSStatusItem, đóng cửa sổ sẽ ẩn khi còn reason, menu mở AMC/SwiftDesk/thoát. Activity token cho phép listener chạy khi cửa sổ ẩn nhưng vẫn cho hệ thống sleep; không giữ máy thức vô hạn. Windows dùng tray sẵn có với menu SwiftDesk và đường quit qua Dart. Thoát hoàn toàn đợi các owner nhả input, đóng capture/signaling và đóng repository nhắc hẹn rồi mới kết thúc native. Plan Studio popup/scheduler trên Windows được giữ; bản này không bổ sung popup reminders macOS.

Các cờ **Giữ host khi đóng cửa sổ**, **Khôi phục host khi mở AMC**, **Khôi phục nhận Internet** độc lập và mặc định tắt. Cổng host được lưu. Startup chỉ mở runtime SwiftDesk khi đã chọn khôi phục host; quyền màn hình thiếu thì không tự nhận phiên/cấp quyền. **Mở AMC khi đăng nhập máy** dùng cài đặt chung; trên Mac chỉ cho đăng ký từ Applications và có thể cần xác nhận Login Items. Không thêm LaunchDaemon/root helper hoặc bật autostart trên máy phát triển trong lúc kiểm thử.

Import file `swiftdesk-config.json` do người dùng chọn: giới hạn 1 MB/500 entry, preview chỉ tên/IP/cổng/platform, một lần lưu metadata; import lại không thêm trùng hoặc đè alias đã nhập. Không đọc/copy `password`, `hostSecret`, `savedPassword`, token, trusted controllers. Máy nhập mang trạng thái cần ghép lại; cloud ID cũ chỉ là ghi chú địa chỉ. File nguồn giữ nguyên. Dữ liệu LAN và secret adapter Phase 1/2 tiếp tục dùng schema cũ; metadata cloud/import/các cờ nằm dưới namespace `swift_desk.*`.

Installer macOS kèm quickstart SwiftDesk, quyền OS và giải thích tùy chọn nền. Bản build Flutter tăng dần từng làm chữ ký ngoài app không khớp sau khi App.framework thay đổi; installer nay ký lại lớp ngoài rồi kiểm tra toàn bộ chữ ký. Đóng gói ad-hoc phục vụ kiểm thử; Developer ID/notarization, nâng cấp qua bộ cài và Windows installer vẫn cần nghiệm thu trên máy nhận. Không tự cài bản build vào Applications hoặc thay app người dùng đang chạy.

## Kiểm chứng và giới hạn

Kết quả Phase 3/4 ban đầu ngày 26/10/2026 nằm trong [bằng chứng xác nhận](evidence/swiftdesk-phase34-validation-2026-10-26.json). Sau yêu cầu giữ P2P IPv6, bản mới nhất có [bằng chứng riêng cho các tùy chọn mạng và bộ cài](evidence/swiftdesk-ipv6-options-validation-2026-10-26.json):

| Kiểm tra | Kết quả |
|---|---|
| SwiftDesk + hồi quy Plan Studio/reminder/settings sau bổ sung IPv6 | 82 đạt, gồm 59 test SwiftDesk |
| Worker integration và TypeScript | 21 test đạt; typecheck đạt |
| Toàn bộ test AMC trước bổ sung tùy chọn IPv6 | 985 đạt, 16 bỏ qua, 25 lỗi trùng chính xác danh sách lỗi nền ngày 23/10; bộ 82 test liên quan chạy lại sau thay đổi IPv6 |
| Phân tích mã | Core không có vấn đề; root còn 3 cảnh báo/thông tin cũ, không có lỗi SwiftDesk mới |
| Release macOS universal | Build đạt; chữ ký toàn app hợp lệ |
| Media thật sau bổ sung IPv6 | Tự động 3/3, Chỉ P2P IPv6 3/3 và LAN 3/3 phiên; stats hai đầu là `direct-ipv6` trên một Mac |
| Vòng đời macOS | Đóng cửa sổ vẫn sống, khôi phục cửa sổ được, Cmd+Q chạy callback dọn dẹp rồi thoát |
| DMG | Kiểm checksum, mount chỉ đọc, chữ ký hợp lệ, có quickstart; executable và Dart AOT trùng bản Release đã thử |

Đã có test crypto pin/tamper/replay/cleanup, admission/owner/ticket/revoke/TURN TTL trên Worker, reason chạy nền, import không secret/idempotence, clipboard ACK và thu hồi khi API mất. Paste đang chờ bị hủy khi nhả quyền điều khiển, kể cả khi lấy quyền lại ngay sau đó. Toàn bộ test AMC chưa xanh vì 25 lỗi nền trên; danh sách đối chiếu có trong evidence.

Kiểm tra cửa sổ dùng bundle preview riêng và reason nền tạm, không mở host hoặc đổi cài đặt thật. Nút đóng ẩn cửa sổ; timer chẩn đoán gọi cùng hàm native khôi phục cửa sổ. Đã xác nhận tiến trình còn sống khi ẩn và kết thúc sau Cmd+Q; chưa kiểm bấm trực tiếp mục menu bar. Bản thử và Worker cục bộ đã dừng sau khi kiểm tra.

Cloud smoke dùng hai account/identity tạm, repository tạm và Worker D1/DO cục bộ; chạy WebSocket + mã hóa thực + WebRTC video và hai DataChannel thực trên một Mac. Ba vòng ghép mới/ghi nhớ/kết nối lại, input giả trên view-only bị chặn, ngắt sạch, thu hồi rồi từ chối ticket. Không tiêm OS input hay dùng kho production. Các phiên cuối xác nhận ít nhất một frame thật mỗi phiên, chưa đo chất lượng/hiệu năng liên tục. Không coi đây là kiểm thử Internet khác mạng hoặc force-TURN.

Đợt IPv6 chạy lại harness ở chế độ Tự động và Chỉ P2P IPv6. Chế độ chỉ IPv6 còn kiểm tra cả stats host/viewer trước khi ghi nhận thành công; TURN không được cấu hình trên Worker cục bộ. Đây là đường IPv6 thực trên cùng máy, chưa chứng minh IPv6 công cộng giữa hai ISP. Test bổ sung kiểm candidate IPv4/IPv6/mapped/mDNS/relay, không fallback khi thiếu IPv6, hai lựa chọn xung đột, truyền ý định trong signaling mã hóa, lưu/khôi phục lựa chọn và UI giữ đúng mode khi lưu thất bại.

Các lần thử trong quá trình phát triển từng gặp timeout khi chưa nhận frame. Đã sửa việc gắn texture viewer trước khi đợi frame, dùng số frame video đã giải mã để xác nhận khi native callback bị bỏ lỡ, và cho phép lấy lại capture đúng một lần trong lúc thương lượng. Vẫn timeout sau 25 giây và không cấp input nếu chưa có hình. Chín phiên cuối không cần retry capture; đường retry có test riêng và không được tính là đã có hình.

Còn gate: Windows compile/hardware, Win↔Mac hai chiều, Accessibility/input thật, DPI/IME, sleep/lock/recovery, hiệu năng và soak 60 phút/20 reconnect, TURN khác mạng/UDP bị chặn/TLS 443, login item/upgrade trên bản ký và Windows tray/installer. Backend còn audit metadata và refresh TURN/resume cho phiên dài. Không đánh dấu hoàn tất nghiệm thu Phase 3/4 khi còn các gate này.

## Chạy lại cục bộ

Không dùng thư mục persistence production; server mặc định vẫn `DESKTOP_ENABLED=false`.

```bash
cd cloudflare/amc-api
npm run typecheck
npm test
npx wrangler d1 migrations apply amc-relay --local --persist-to /tmp/amc-desktop-test
npx wrangler dev --local --persist-to /tmp/amc-desktop-test --port 18779 \
  --var DESKTOP_ENABLED:true --var PASSWORD_PEPPER:local-disposable-test
```

Trong terminal khác ở repo AMC:

```bash
flutter build macos --release
codesign --force --sign - --entitlements macos/Runner/Release.entitlements \
  'build/macos/Build/Products/Release/App Management Center.app'
codesign --verify --deep --strict \
  'build/macos/Build/Products/Release/App Management Center.app'
'build/macos/Build/Products/Release/App Management Center.app/Contents/MacOS/App Management Center' \
  --swiftdesk-cloud-smoke-api=http://127.0.0.1:18779 \
  --swiftdesk-cloud-smoke-report=/tmp/amc-cloud-smoke.json
```

Smoke từ chối host khác `127.0.0.1`; HTTP/WS chỉ được phép trong harness này với dữ liệu disposable. UI Internet thông thường bắt buộc HTTPS/WSS. Quyền Screen Recording cần được cấp trước cho binary AMC; harness không bật quyền hay yêu cầu input.

Thêm `--swiftdesk-cloud-smoke-mode=directIpv6` vào lệnh smoke để kiểm chứng P2P IPv6 bắt buộc. Bài thử phải có frame thật và stats hai đầu là IPv6; môi trường không có candidate/đường IPv6 sẽ thất bại thay vì chuyển sang IPv4 hoặc TURN. Báo cáo và dữ liệu của harness vẫn tách biệt cài đặt thật.

## Chuẩn bị staging/TURN

Xem [mẫu coturn](../infra/turn/turnserver.conf.example). Thay realm/IP public/NAT/cert và secret bằng cấu hình thật, giữ secret ngoài Git. Mở 3478 UDP/TCP, 443 TCP/TLS và dải relay 49160–49200 UDP trên máy TURN. TLS 443 yêu cầu hostname/cert hợp lệ; TURN không được đặt sau proxy HTTP thông thường. Cấu hình mẫu chưa được chạy bằng coturn trong môi trường này.

API cần `TURN_URLS` (các URL `turn:`/`turns:` cách dấu phẩy), `STUN_URLS` (ví dụ `stun:turn.your-domain:3478`) và secret `TURN_SECRET` giống `static-auth-secret`. Ví dụ URL TURN: `turn:turn.your-domain:3478?transport=udp,turn:turn.your-domain:3478?transport=tcp,turns:turn.your-domain:443?transport=tcp`. Dùng tài nguyên staging trước; migration D1 và migration DO phải có trước khi bật `DESKTOP_ENABLED=true`. Đợt này chưa chạy migration remote, upload secret, deploy Worker, mở firewall hoặc cài coturn.

Sau khi có staging: đăng ký hai máy/tài khoản thử, ghép bằng mã qua kênh tin cậy, thử P2P rồi bật bắt buộc TURN trên hai máy trước phiên mới. Xác nhận stats là `relay`, chặn UDP để kiểm TLS 443, thu hồi giữa phiên và thử lại; không dùng trạng thái connected của signaling làm bằng chứng nhận hình.

Thiết kế đối chiếu [Cloudflare WebSocket hibernation](https://developers.cloudflare.com/durable-objects/best-practices/websockets/) và [coturn TURN REST credentials](https://github.com/coturn/coturn/wiki/turnserver). Đây là nguồn về API/cách cấp credential; kết quả chạy AMC nằm trong evidence của repo.
