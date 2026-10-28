# Kế hoạch đưa SwiftDesk thành core module của AMC

Ngày cập nhật: 26/10/2026. Đã triển khai core/LAN Phase 1/2 và tiếp tục mã Internet/chạy nền Phase 3/4 trong AMC. Có kiểm thử Worker cục bộ + WebRTC trên macOS, còn gate hai máy, Windows, TURN thật, input và bộ cài trên máy nhận. Chưa deploy Internet production hoặc cài service hệ thống.

## Tiến độ Phase 3 và 4

- Đối chiếu upstream tới `origin/main` `53ba594`, giữ nguyên repo nguồn. Bổ sung Ctrl phải/clipboard trước paste, chặn instance Release macOS khởi tạo lần hai và cài đặt nền; không port root helper/public MQTT.
- Có enrollment theo account/fingerprint, ID server cấp, WSS Durable Object, ticket một lần, approval/ACL/revoke/rate/quota, TURN credentials 15 phút và signaling mã hóa tới host. Backend feature flag mặc định tắt; chỉ chạy D1/DO cục bộ trong đợt này.
- Có AppBackgroundService dùng chung Plan Studio/SwiftDesk, menu bar Mac, tray Windows, quit đợi cleanup, opt-in khôi phục LAN/Internet, startup Mac qua SMAppService và Windows qua shortcut AMC hiện có.
- Có import metadata có preview/idempotence/không secret, quickstart trong DMG, stats đường truyền thật và mẫu coturn. Người dùng xác nhận chưa có TURN, chọn chuẩn bị mẫu và test local.
- Giữ P2P IPv6 của SwiftDesk: có chọn Tự động (IPv6/IPv4 và TURN dự phòng), Chỉ P2P IPv6 hoặc Bắt buộc TURN; lưu lựa chọn qua lần mở lại và giữ cài đặt force-TURN cũ. Chế độ IPv6 trực tiếp không cần TURN, vẫn xác thực/duyệt phiên qua API AMC.
- Bằng chứng, cách chạy lại, staging và gate còn lại: [Phase 3/4](swiftdesk-phase34.md). Các hạng mục backend/installer vẫn để chưa nghiệm thu hoàn tất cho tới khi có kiểm thử khác mạng/hai OS/bản cài ký.

## Tiến độ Phase 1 và 2

- Core Dart độc lập Flutter: models, ports, state machine, policy theo phiên/scope/thời hạn và protocol input v1. Runtime do app sở hữu, không phụ thuộc HomeController.
- Có engine WebRTC, hai DataChannel, permission/native input Win/macOS, cleanup khi mất focus/kết nối, đổi display/chất lượng, clipboard văn bản theo quyền riêng.
- Có TLS LAN ghim SHA-256 chứng chỉ, mã ghép 5 phút dùng một lần, chấp nhận thủ công mỗi phiên, nhớ thiết bị, lưu token qua adapter bảo mật AMC, thu hồi và lịch sử metadata.
- Entry chính đã đổi thành **SwiftDesk · Điều khiển máy tính**; host giữ khi rời trang, có trạng thái/duyệt yêu cầu toàn AMC. Thoát AMC dừng host. Tray/autostart/import SwiftDesk cũ thuộc Phase 4.
- Debug và Release macOS build thành công. Release đã qua 3 phiên TLS + video thật + hai DataChannel, kết nối đã nhớ, đổi chất lượng, ngắt sạch và từ chối credential bị thu hồi. Không tiêm input OS trong bài thử này.
- Tiếp tục Phase 1/2 theo yêu cầu người dùng với engine ứng viên đã chạy được cục bộ; đây chưa phải xác nhận đủ gate Win↔Mac/force-TURN của Phase 0 hoặc đủ nghiệm thu Phase 2. Windows chưa build/chạy trên máy Windows; Accessibility của binary kiểm thử hiện vẫn false.
- Cách dùng, ADR LAN, kiểm thử và các việc nghiệm thu còn lại: [SwiftDesk LAN](swiftdesk-lan.md).

## Kết quả Phase 0 trước khi triển khai LAN

- Đã build baseline AMC và SwiftDesk trên macOS. Có 3 cảnh báo phân tích và 6 test power lỗi sẵn trên macOS; không tính là regression của SwiftDesk.
- Đã thêm trang **SwiftDesk · Thử kết nối**; hiện mở qua nút thử engine trong module hoặc `--swiftdesk-spike`, bỏ qua account, relay lệnh, Telegram và reminders.
- Đã tạo nền `amc_remote_core` (protocol input có version, kiểm tra payload, gate theo phiên/expiry/sequence) và `amc_remote_platform` (permission, pointer/Unicode có scope phiên). Đây là phần phục vụ spike; chưa phải core API production hoàn chỉnh ở mục 4.
- Đã thử capture ScreenCaptureKit → WebRTC → render và DataChannel trên macOS. Ba vòng mở–dừng đều nhận frame thật, có phản hồi kênh dữ liệu và dừng capture. Native từ chối input chưa có grant. Màn hình ít thay đổi; chưa kết luận 30/60 FPS.
- Đã thêm trao đổi offer/answer thủ công và chế độ force-TURN để chạy ma trận hai máy. Chưa kiểm chứng đường hai máy, Windows, TURN hoặc thao tác native thực tế vì thiếu quyền Accessibility/hạ tầng đối ứng.
- Engine vẫn là ứng viên đang đánh giá. Chưa đạt tiêu chí kết thúc Phase 0; không tự chuyển sang phát hành Internet/unattended.
- Hướng dẫn, kết quả và các điều kiện còn lại: [Thử engine SwiftDesk](swiftdesk-engine-spike.md).

## 1. Mục tiêu và quyết định kiến trúc

Đưa **SwiftDesk · Điều khiển máy tính** thành một chức năng chính của AMC: mở ngay trong giao diện AMC, nhận và tạo phiên remote, dùng chung thiết bị, cài đặt, vòng đời chạy nền và bộ cài. Người dùng chỉ cần cài AMC.

Hướng chính là **port nghiệp vụ sang Dart/Flutter và viết adapter native**, có bước thử nghiệm engine trước. SwiftDesk hiện là Electron + TypeScript nên không thể chép nguyên module vào Flutter. Electron sidecar chỉ là phương án dự phòng có thời hạn nếu thử nghiệm capture/WebRTC thất bại; không coi việc mở app SwiftDesk bên ngoài là đã hoàn thành tích hợp.

“Core module” ở đây có ba yêu cầu cụ thể:

1. Core có API độc lập với trang giao diện, dùng được từ desktop, mobile và các chức năng khác của AMC.
2. Runtime thuộc vòng đời ứng dụng: rời trang vẫn giữ phiên; host đã bật vẫn nhận kết nối khi AMC chạy nền.
3. Tài nguyên native, quyền truy cập, cài đặt và dữ liệu được AMC quản lý; không có hai cơ chế tray/autostart tranh nhau.

## 2. Hiện trạng đã đọc từ source

| Thành phần | Đã thấy trong code | Hệ quả cho tích hợp |
|---|---|---|
| SwiftDesk | `/Users/witherdragon/Work/source/window_mac/amc_remote`, package `swiftdesk-remote` 1.1.0 | Đây là source cần chuyển; tên thư mục khác tên sản phẩm |
| Host/signaling | `src/main/signaling-server.ts`: HTTP/WebSocket trực tiếp, MQTT cloud, xác thực và danh sách phiên | Tách protocol, transport và policy; không port nguyên server vào UI |
| Media/viewer | `src/renderer/app.ts`: capture, WebRTC, input DataChannel, relay frame và UI cùng một file | Port theo trách nhiệm và state machine, không chuyển từng dòng |
| Input | `src/main/input-controller.ts`: `koffi`, Win32 và Quartz, map phím, Unicode, release input | Tận dụng quy tắc và ca kiểm thử; phần gọi OS chuyển sang plugin C++/Swift |
| ICE | `RTC_CONFIG` trong renderer chỉ có STUN; không có TURN credential đang được cấu hình | README nói P2P/TURN không đủ để kết luận TURN hoạt động |
| Cloud fallback | Frame có đường relay qua broker MQTT công cộng; `publishCloud` gửi JSON | Thay bằng TURN có xác thực; không dùng broker hiện tại cho production AMC |
| Secret | `store.ts` ghi config JSON có password, host secret và saved devices; model có `savedPassword`/`trustToken` | Không nhập nguyên config vào preference AMC; thiết kế lưu secret và ghép lại thiết bị |
| AMC | Flutter/GetX, module tại `lib/app/modules/`, runtime dài hạn như `QaDeskRuntime` | Dùng cùng mẫu tích hợp runtime, theme và command palette |
| Remote hiện có | `RemoteControlService`: relay mobile, release, nguồn, wake, unlock, build iOS | Thêm capability desktop; không gom media/input vào service đang có |
| Background Windows | Tray/ẩn cửa sổ nằm trong runner và channel `amc/plan_reminders` | Cần tách quyền sở hữu chạy nền ra cấp ứng dụng |
| Background macOS | `AppDelegate.applicationShouldTerminateAfterLastWindowClosed` trả `true` | Đóng cửa sổ hiện làm app thoát; phải bổ sung menu bar và chính sách đóng cửa sổ |
| Credential AMC | `SecureKeyValueStore.platform()`: Windows dùng secure storage; macOS dùng `EncryptedFileSecretStore` | Dùng abstraction hiện tại, đánh giá bảo vệ khóa cho unattended access; không mặc định macOS đang dùng Keychain |
| Backend AMC | Có `cloudflare/amc-api` cho account/team/API/vault; relay lệnh là endpoint khác | Xây capability signaling riêng, không đưa video vào hàng đợi lệnh |

Phần khảo sát ban đầu chỉ đọc source và tài liệu. Sau đó đã build trên macOS và kiểm thử cục bộ theo các mục tiến độ phía trên. Chưa đo hiệu năng/độ trễ trên hai máy. Không coi các số “60 FPS”, “0.1 ms” trong README gốc là kết quả đo.

## 3. Phạm vi theo đợt

**Bản desktop đầu tiên:** Windows/macOS vừa làm host vừa làm viewer; xem màn hình, chuột/phím, cuộn, Unicode tiếng Việt, nhiều màn hình nhưng chọn một màn hình mỗi phiên; ID thiết bị, LAN/IP, thiết bị đã lưu, ghép nối, thu hồi quyền, clipboard văn bản có công tắc, tự reconnect có giới hạn, thông tin chất lượng phiên. Mỗi host có tối đa một controller đang điều khiển; có thể vừa host vừa viewer nếu thử nghiệm xác nhận ngân sách tài nguyên phù hợp.

**Sau bản desktop ổn định:** Android làm viewer ngay trong AMC mobile, nút “Mở màn hình” từ máy tính đã liên kết, đồng bộ danh bạ thiết bị theo team và liên kết phiên với tác vụ hỗ trợ/QA.

**Đợt riêng:** đăng nhập trước khi có user session, điều khiển UAC/secure desktop, macOS loginwindow, dịch vụ hệ thống, âm thanh, truyền file, ghi hình và nhiều controller đồng thời. SwiftDesk có script loginwindow thử nghiệm; không đưa script đó vào bộ cài mặc định. iOS viewer và mobile host chưa nằm trong kế hoạch triển khai ban đầu.

## 4. Cấu trúc đề xuất

```text
AMC/
  packages/
    amc_remote_core/                 # Dart thuần, không Flutter/GetX
      lib/src/{models,protocol,session,ports}/
      test/
    amc_remote_platform/             # Flutter plugin: input, quyền, display OS
      lib/
      windows/
      macos/
  lib/app/modules/swift_desk/
    controllers/
    views/                          # Trang chính và màn hình phiên remote
    widgets/
    services/                       # Runtime, repository, credential adapter
    infrastructure/                 # WebRTC engine, signaling, native adapter
  lib/app/services/
    app_background_service.dart     # Dùng chung Plan Studio/SwiftDesk
    amc_remote_desktop_host.dart    # Adapter account/device/capability AMC
  cloudflare/amc-api/src/
    remoteDesktop.ts               # Đề xuất: device enrollment, ticket, ACL
  cloudflare/amc-signaling/          # Đề xuất: WebSocket + Durable Objects
```

Không bắt buộc tạo framework đăng ký module chung cho toàn bộ AMC. Chỉ thêm các contract cần cho SwiftDesk và dịch vụ background dùng chung.

### Ranh giới core

- `RemoteDevice`, `RemoteSession`, `DisplayDescriptor`, `RemoteCapabilities`, `RemoteInputEvent`, `SessionStats`.
- Ports: `RemoteDesktopEngine`, `SignalingTransport`, `RemoteDeviceRepository`, `RemoteCredentialStore`, `RemoteAccessPolicy`.
- Runtime API dự kiến: `initialize`, `enableHost`, `disableHost`, `connect`, `accept`, `reject`, `disconnect`, `revokeDevice`, `shutdown`; stream trạng thái và sự kiện phiên.
- State machine: `idle → requesting → awaitingApproval → negotiating → connected → reconnecting → ended/failed`. Chỉ đi vào `connected` khi có xác thực và media thực sự hoạt động; hủy/từ chối/timeout có đường kết thúc rõ ràng.
- Mỗi session có ID, protocol version, endpoint identities, scope, expiry và trạng thái input riêng. Không dùng ID hiển thị 9 số như bằng chứng nhận dạng.
- Core không phụ thuộc `HomeController`, widget hay HTTP client AMC. Adapter AMC cung cấp account, team, thiết bị và chính sách qua interface.

### Engine và native

Ưu tiên thử `flutter_webrtc` cho capture, encode/decode, render và DataChannel. Đây là lựa chọn cần qua spike trên AMC hiện tại, chưa chốt version hay bảo đảm tương thích. Không truyền frame thô qua MethodChannel; đường media dùng engine/texture của plugin.

`amc_remote_platform` xử lý input và capability OS: Win32 `SendInput`; macOS Quartz/Accessibility; permission diagnostics, tọa độ màn hình và release phím. Batching/coalescing mousemove để tránh mỗi pixel là một lần gọi native. Core chịu trách nhiệm authorize/validate trước khi native nhận event.

Hai kênh input kế thừa ý tưởng SwiftDesk: mousemove ưu tiên độ trễ, unordered và bỏ gói cũ; key/button/text/clipboard ordered, reliable. Sequence tách theo session. Mất kết nối, đổi display, mất quyền hoặc đóng viewer đều phải nhả modifier/button đang giữ. Clipboard đi qua kênh có quyền riêng, giới hạn kích thước và chặn vòng lặp.

## 5. Kết nối và quyền truy cập

Luồng dự kiến:

```text
Viewer AMC ── WSS / ticket / offer / ICE ── AMC Signaling ── Host AMC
Viewer AMC ═════ WebRTC video + input (P2P hoặc TURN) ═════ Host AMC
```

Signaling chỉ chuyển metadata/SDP/ICE. TURN chuyển gói media khi P2P không đi được; API/relay lệnh hiện có không chở video. Cloudflare Durable Objects là ứng viên cho signaling có trạng thái WebSocket; TURN cần dịch vụ chuyên biệt được cấp phát riêng.

1. Mỗi installation có UUID/key pair; cloud cấp ID hiển thị ngắn duy nhất có xử lý collision. Namespace mới của AMC, không hứa giữ nguyên ID SwiftDesk cũ.
2. Mặc định host tắt. Lần đầu dùng mã ghép nối ngắn hạn và host chấp nhận, kèm fingerprint/identity binding; LAN không có account dùng QR/mã xác minh để pin peer identity.
3. Account/team chỉ cho phép khám phá thiết bị trong phạm vi; không tự cấp quyền điều khiển tất cả máy cùng team.
4. Ticket phiên ràng buộc host/viewer, scopes, nonce, expiry; bảo vệ replay, rate limit và giới hạn số phiên. Ràng buộc SDP fingerprint vào peer đã được xác minh; DTLS media không thay thế bước xác minh danh tính.
5. Unattended access chỉ bật riêng trên host sau khi trust thiết bị; credential có scope, thu hồi và hết hạn/rotate. Không đưa mật khẩu hệ điều hành, token hoặc SDP vào log thường.
6. Scope mới: `desktop.view`, `desktop.input`, `desktop.clipboard`; quyền run/power/unlock của AMC vẫn được kiểm tra riêng. Thiết bị mobile đã ghép cũ không tự nhận quyền desktop.
7. TURN dùng credential ngắn hạn, hỗ trợ lộ trình UDP và TLS/TCP 443 theo hạ tầng thực tế; đo băng thông và quota trước rollout. Không bật UPnP tự động mặc định.
8. Đường LAN/IP cũng phải xác minh peer và bảo vệ signaling; không port cơ chế gửi password qua `ws://` hiện tại. Thiết kế cụ thể TLS/pinning được chốt trong spike protocol trước MVP LAN.
9. Bản đầu dùng pairing/trust thay mật khẩu cố định làm mặc định. Nếu cần giữ kết nối bằng mật khẩu, bổ sung thiết kế challenge/PAKE đã được review; không tự chế thuật toán hay copy password plaintext.

## 6. Trải nghiệm trong AMC

- Entry “SwiftDesk · Điều khiển máy tính” cạnh QA Desk/Plan Studio trong Công cụ dự án, menu công cụ và command palette; dùng theme Console/Cyber/Default cùng scaling hiện có.
- Trang chính có “Máy tính này” (ID, bật nhận kết nối, quyền màn hình/chuột phím), “Kết nối máy khác” và “Thiết bị đã lưu”. Trạng thái có lý do cụ thể: offline, chưa cấp quyền, đang có người điều khiển, hết hạn ghép nối.
- Viewer có chọn display, fit/1:1, chất lượng, toàn màn hình, clipboard, thống kê và ngắt kết nối. Zoom/letterbox/DPI không làm lệch tọa độ input.
- Host luôn có dấu hiệu đang bị truy cập và nút ngắt tại máy. Nút này vẫn dùng được khi đang build hoặc đang ở module khác.
- Rời trang danh bạ không dừng host. Đóng màn hình viewer kết thúc phiên outbound và release input; muốn ẩn mà giữ phiên dùng hành động thu nhỏ rõ ràng.
- V1 ưu tiên một route viewer trong cửa sổ AMC. Cửa sổ native tách riêng là cải tiến sau, tránh đưa multi-window vào đường găng capture.
- Android đợt sau có “Mở màn hình” trên thiết bị đã liên kết, trackpad/chạm, bàn phím và phím chức năng; không giả định mobile capture/host đã được hỗ trợ.

## 7. Dùng chung vòng đời và chức năng AMC

`SwiftDeskRuntime` mở lười khi vào module. Nếu host đã được bật từ trước, startup khởi động phần host tối thiểu không cần mở trang; không bắt mọi lần launch tải capture engine. Chỉ tạo stream sau khi phiên được chấp nhận.

`AppBackgroundService` quản lý một tray/menu bar và các lý do cần giữ app sống như `planReminders`, `remoteHost`, `activeRemoteSession`. Tắt nhắc hẹn không làm mất remote host. “Thoát AMC” phải ngắt phiên, nhả input, đóng capture/peer/signaling rồi mới thoát. `PlanStudioRuntime` chuyển sang dùng service chung bằng adapter, giữ cài đặt người dùng.

Windows tái sử dụng cơ chế autostart của AMC; macOS bổ sung login item/agent cho phiên user, không cài loginwindow service. Đóng cửa sổ khi có yêu cầu chạy nền sẽ ẩn app; khi không có sẽ theo chính sách thoát của AMC. Trạng thái này phải được kiểm tra trong bản đóng gói, không chỉ widget test.

`RemoteControlService` chỉ bổ sung khả năng truy vấn/mở phiên desktop qua adapter. Power/wake/unlock tiếp tục đi qua policy hiện tại. Máy đang ngủ/offline không thể nhận video; wake là tác vụ riêng. Phiên view đang chạy không khóa hàng đợi build. Không tự gộp trusted device SwiftDesk với pairing mobile AMC bằng hostname hay ID hiển thị.

## 8. Lưu trữ và chuyển dữ liệu

- Metadata thiết bị, setting và lịch sử phiên trong `<AppSupport>/swift_desk/`, có schema version. Có thể dùng SQLite sẵn trong AMC; preference chỉ giữ lựa chọn nhỏ và cờ host.
- Token, private key và trust secret đi qua `RemoteCredentialStore` bọc abstraction bảo mật của AMC; không vào SQLite/preference/export. Riêng unattended phải đánh giá cách lưu khóa macOS trước khi bật cho production.
- Nhập dữ liệu SwiftDesk bằng thao tác “Nhập thiết bị cũ”: preview, chọn file/folder người dùng chỉ định, chỉ đọc alias/địa chỉ/platform. Bỏ `password`, `savedPassword`, `hostSecret`, `trustToken`, `trustedControllers`; thiết bị phải ghép lại.
- Import transactional/idempotent, không đè bản ghi đã sửa, giữ nguyên dữ liệu nguồn. Khi chưa có ánh xạ identity đã xác minh, ID cloud cũ chỉ là ghi chú và không dùng để kết nối vào namespace AMC.
- Kiểm tra nguồn giấy phép trước port: `package.json` ghi MIT nhưng cần xác nhận LICENSE/quyền sử dụng thực tế và giữ attribution phù hợp.

## 9. Lộ trình và điều kiện nghiệm thu

Ước lượng dưới đây là ngày công sơ bộ cho một người quen codebase, có sẵn một máy Windows và một máy macOS. Không phải cam kết lịch; chưa gồm mua/cấp hạ tầng hoặc chờ ký ứng dụng. Chốt lại sau Phase 0.

| Mốc | Việc chính | Hoàn thành khi | Ước lượng |
|---|---|---|---|
| Phase 0 — spike | Build baseline; thử capture/render/DataChannel/native input trên AMC; xác minh plugin, ABI, minimum OS, CPU/GPU và đường TURN | Có phiên Win↔Mac hai chiều, nhận frame thật, input đúng, permission-denied rõ ràng, force-TURN được; ghi ADR chọn engine | 3–5 ngày |
| Phase 1 — core | Core package, protocol v1, state machine, policy, native plugin, storage/secret adapter và runtime | Core test độc lập; input chưa authorize bị từ chối; disconnect luôn cleanup; module không cần HomeController | 4–6 ngày |
| Phase 2 — desktop LAN | UI AMC, pairing an toàn, LAN/IP, host/viewer, nhiều display/DPI, bàn phím Việt, saved devices và clipboard text | Kết nối Win↔Win, Mac↔Mac, Win↔Mac trong LAN; rời trang không mất host; lỗi capture không báo connected giả | 5–8 ngày |
| Phase 3 — Internet | Enrollment/ID, signaling WSS, identity binding, ACL/ticket, TURN credential, revoke/rate limit | Hai máy khác mạng kết nối P2P và force-TURN; không có password/frame qua broker công cộng; thu hồi chặn được phiên/kết nối mới theo policy | 5–8 ngày |
| Phase 4 — core AMC hoàn chỉnh | Background service chung, autostart, trạng thái toàn app, import, installer, recovery | Bộ cài sạch hoạt động trên cả hai OS; Plan Studio và remote cùng chạy nền; upgrade không mất thiết bị; tắt feature không ảnh hưởng remote lệnh cũ | 4–6 ngày |
| Phase 5 — mobile/team | Android viewer, liên kết danh bạ có xác minh, scope migration và team metadata | Mobile chỉ thấy/mở thiết bị đúng quyền; pairing cũ cần nâng quyền rõ ràng; desktop regressions qua | 4–7 ngày |

Đường găng tới desktop tích hợp đầy đủ khoảng **21–33 ngày công**, sau đó mobile/team khoảng **4–7 ngày công**. Một demo LAN có thể có sớm hơn nhưng chưa đủ tiêu chuẩn phát hành Internet. Nếu Phase 0 thất bại, dừng việc port UI quy mô lớn và chọn lại engine/sidecar có thời hạn cùng tiêu chí gỡ bỏ; không tiếp tục dựa trên giả định capture chạy được.

## 10. Backlog triển khai

- [ ] SD-001: Ghi baseline build/test hai repo, kiểm giấy phép và ma trận OS/CPU.
- [ ] SD-002: Spike Flutter WebRTC + native input trên bản AMC đóng gói, đo frame sống và tài nguyên.
- [ ] SD-003: ADR engine, identity/pairing, LAN signaling an toàn và Internet/TURN; pin dependency sau spike.
- [x] SD-004: Tạo `amc_remote_core`, ports và session/protocol state machine có version.
- [ ] SD-005: Plugin native Win/macOS: quyền, tọa độ, Unicode/modifier, input cleanup.
- [ ] SD-006: Engine adapter, hai input channel, render/stats, reconnect và display switch.
- [ ] SD-007: Device repository, credential adapter, migration/import chỉ metadata.
- [x] SD-008: SwiftDeskRuntime + entry UI, permission onboarding và host status toàn app.
- [ ] SD-009: MVP LAN có pairing/identity verification và kiểm thử hai máy.
- [ ] SD-010: Backend enrollment/ACL/ticket/signaling, TURN credential, quota và audit metadata.
- [ ] SD-011: Tách background service dùng chung; migrate Plan Studio; macOS menu bar/autostart.
- [ ] SD-012: Đóng gói, ký/permission regression, upgrade/recovery, rollout flag.
- [ ] SD-013: Android viewer và scope mới cho thiết bị ghép cũ.
- [ ] SD-014: Đồng bộ metadata team và ánh xạ identity, không đồng bộ secret raw.

## 11. Kiểm chứng và rollout

**Tự động:** core kiểm tra chuyển trạng thái, timeout/replay, session routing, scope, reconnect, sequence cũ, cleanup phím và serialization có giới hạn. Adapter test signaling bằng server cục bộ, xác thực/revoke/rate limit backend, secret không rò qua export/log. Widget test ghép nối, từ chối, offline/permission, ngắt phiên và theme. Regression chọn các nhóm remote control/power/unlock, Plan Studio background, app settings và lifecycle bị tác động.

**Hai máy thật:** Win↔Win, Mac↔Mac và Win↔Mac hai chiều; LAN, Internet khác mạng, force-TURN/TLS 443, đổi mạng, mất mạng/host crash, sleep/resume và khóa máy. Kiểm nhiều màn hình/Retina/DPI hỗn hợp/đổi độ phân giải, phím bị giữ khi mất mạng, IME/EVKey/Unikey, clipboard bật/tắt, thu hồi trong phiên, từ chối quyền màn hình/Accessibility. UAC/lock/loginwindow phải hiện capability không hỗ trợ khi engine không xử lý được, không báo thành công giả.

**Mục tiêu đo thử:** phiên 1080p LAN đạt khoảng 30 FPS ổn định khi màn hình chuyển động; 60 FPS là preset/mục tiêu tùy máy. Báo cả bitrate, frame age, dropped frames, CPU/RAM và input-to-visible latency p50/p95 trên cấu hình ghi rõ; không dùng RTT thay cho độ trễ thao tác. Chạy phiên 60 phút và ít nhất 20 vòng reconnect để tìm leak/kẹt phím. Không dùng số đo ước lượng làm kết quả nghiệm thu.

**Rollout:** flag riêng cho module/host/Internet; ban đầu tắt host và chỉ bật nhóm thử nội bộ. Giữ đường remote command cũ hoạt động, migration schema có backup và không sửa dữ liệu SwiftDesk gốc. Khi media lỗi có thể tắt host/Internet mà vẫn dùng release/power/wake bình thường. Chưa có triển khai backend hoặc cài service hệ thống trong bước lập kế hoạch này.

## 12. Tài liệu kỹ thuật đối chiếu

- Flutter WebRTC có API media và hỗ trợ nhiều nền tảng; khả năng thực tế phải xác minh với version và binary AMC: [repository chính thức](https://github.com/flutter-webrtc/flutter-webrtc), [MediaDevices/getDisplayMedia](https://flutter-webrtc.org/docs/flutter-webrtc/api-docs/media-devices/).
- Capture native macOS tham chiếu [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos); không suy ra quyền capture tự động khi đổi bundle/signature.
- Microsoft nêu `SendInput` chịu giới hạn UIPI và mức integrity: [SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput). Vì vậy remote ứng dụng nâng quyền là hạng mục riêng.
- Signaling WebSocket có trạng thái tham chiếu [Cloudflare Durable Objects WebSockets](https://developers.cloudflare.com/durable-objects/best-practices/websockets/). Đây là đề xuất hạ tầng signaling, không thay thế TURN.

Tiếp theo cần nghiệm thu native input sau khi cấp Accessibility và ma trận LAN Win↔Win, Mac↔Mac, Win↔Mac. SD-005/006 đã có mã, còn kiểm chứng Windows/display/DPI thực tế; SD-007 đã có repository/credential/import metadata ở Phase 4; SD-009 đã qua loopback nhưng chưa đủ tiêu chí hai máy. SD-010/011/012 có mã và kiểm thử cục bộ, còn gate staging/TURN/hardware/bộ cài; giữ chưa đánh dấu nghiệm thu hoàn tất. Phase 3 chưa bật production khi chưa có TURN và kiểm chứng danh tính/vượt NAT trên hạ tầng thật.
