# Kế hoạch hoàn thiện điều khiển máy tính từ điện thoại

Ngày: 2026-09-21. Trạng thái: **Phase 0, 1 và 2 đã triển khai**, Phase 3–4 chưa. Nhánh: `feature/flowfin-module-rebrand`.

## Kiểm chứng đầu-cuối và hai lỗi nó tìm ra

`test/remote_control_e2e_test.dart` khởi động **relay Node thật** rồi cho cả agent máy tính lẫn vai điện thoại chạy qua nó. Mọi test khác đều giả lập một đầu dây; test này không. Sáu ca: tắt máy đầu-cuối, khóa máy trong lúc release đang chạy, tắt máy bị từ chối khi đang build, cổng quyền đóng thì máy từ chối, thiếu scope thì relay chặn, và chẩn đoán đánh thức đi hết đường về điện thoại.

Nó tìm ra hai lỗi mà unit test không thể thấy:

1. **Long-poll luôn chết vì timeout.** Client GetConnect mặc định 5 giây, `ReleaseCenterConnect.onInit` đặt 20 giây, còn relay giữ cửa sổ 20 giây. Hai con số bằng nhau nghĩa là *mọi* vòng poll rảnh đều kết thúc bằng TimeoutException, rồi lùi thêm 5 giây. Lệnh nguồn phải chờ tới ~25 giây, và `agentStatus` luôn hiện lỗi dù agent hoàn toàn khỏe. Lỗi này **có từ trước Phase 1**, ảnh hưởng cả lane release. Đã sửa: cửa sổ 12 giây, timeout 30 giây, đặt trong constructor thay vì `onInit` để client dựng trực tiếp cũng đúng, và một poll hết giờ không còn bị coi là lỗi.
2. **Test ghi vào Firestore thật.** `serverless/notifications/.env` có `FIREBASE_SERVICE_ACCOUNT_JSON_B64`, và `hasFirestoreConfig` chỉ cần một trong ba khóa là chuyển sang Firestore. Tôi chỉ xoá `FIREBASE_PROJECT_ID` nên relay của test vẫn nối vào Firestore production — biểu hiện ra ngoài là mỗi request mất ~1,4 giây. Đã xoá cả ba khóa, **và thêm chốt chặn**: relay phải tạo được file JSON tạm, không thì test dừng ngay thay vì âm thầm ghi lên cloud.

Sau khi sửa: claim tới publish xong còn **10 mili giây**, cả suite sáu ca chạy trong **4 giây** thay vì 80.

## Tiến độ Phase 2

- **RMC-009 xong.** `WakeDiagnosticsService` đọc một lượt bằng PowerShell: card mạng đang dùng, MAC, IPv4 + prefix để tính địa chỉ broadcast, Wake on Magic Packet, Fast Startup, chính sách ARSO, BitLocker PIN trước khởi động. Kết quả đi kèm heartbeat và cache lại, vì điện thoại cần đúng lúc máy đang ngủ và không hỏi được nữa.
- **Tri-state, không phải boolean.** Mỗi cờ có ba trạng thái: bật, tắt, **không đọc được**. Báo "Wake-on-LAN đang tắt" trong khi thực ra chỉ là không đọc được sẽ đẩy người dùng vào BIOS vô ích.
- **RMC-010 xong.** `WakeOnLanService` dựng gói 102 byte và gửi UDP tới cả `255.255.255.255` lẫn broadcast của subnet, trên cổng 9 và 7 — access point khác nhau chặn cái khác nhau. Không thêm dependency, không cần quyền Android nào ngoài `INTERNET`.
- **RMC-011 xong.** Nút Đánh thức chờ heartbeat 90 giây. Thất bại thì mở bảng liệt kê **đúng những thứ đang cản trên máy đó**, mỗi mục kèm cách sửa cụ thể, xếp theo mức nghiêm trọng. Danh sách chỉ hiện sau khi thử thất bại, không dội cảnh báo vào mặt người dùng từ đầu.

### Đính chính: Wi-Fi không phải vật cản như tôi tưởng

Bản đầu của mục này coi Wi-Fi là vật cản gần như tuyệt đối. Kiểm tra máy thật cho thấy tôi sai, và cái sai nằm ở **cách đọc**, không phải ở kết luận chung:

- `Get-NetAdapterPowerManagement` lỗi trên card MediaTek MT7925 nên chẩn đoán trả về "không đọc được". Nhưng `Get-NetAdapterAdvancedProperty -RegistryKeyword '*WakeOnMagicPacket'` đọc được bình thường và cho kết quả **Enabled**. Đã chuyển sang nguồn dữ liệu này.
- `powercfg -devicequery wake_armed` cho thấy Windows **đang cho** card Wi-Fi đó đánh thức máy. Hỗ trợ magic packet và được Windows cho phép là hai chuyện khác nhau, giờ đọc cả hai.
- Máy có S3 thật, không phải Modern Standby.

Nên kết luận đúng không phải "Wi-Fi hỏng" mà là **ranh giới nằm ở trạng thái máy, không ở loại card**:

| Từ trạng thái | Wi-Fi | Ethernet |
|---|---|---|
| Ngủ (S3) / Ngủ đông | Được, nếu card hỗ trợ magic packet và được arm | Được |
| Tắt hẳn | Gần như không, card mất điện | Được, nếu tắt Fast Startup và bật `S5WakeOnLan` |

Model bỏ `wirelessAdapter` khỏi danh sách vật cản và thay bằng hai thuộc tính suy ra: `canWakeFromSleep` và `canWakeFromShutdown`. Khi ngủ đánh thức được mà tắt hẳn thì không, giao diện nói thẳng "Chỉ đánh thức được từ trạng thái Ngủ" kèm hướng dẫn dùng nút Ngủ thay cho Tắt máy — hữu ích hơn nhiều so với một cảnh báo chung chung về Wi-Fi.

Thêm `shutdownWakeOnLan` và `wakeArmed`, đều tri-state. Máy khảo sát: Wi-Fi `S5WakeOnLan` không tồn tại (null), Ethernet có và đang `0`.

### Hai thứ chỉ lộ ra khi chạy thật

Tôi chạy script chẩn đoán trên chính máy này, và nó đổi thiết kế:

1. **Máy đang nối bằng Wi-Fi.** Đánh thức qua Wi-Fi hầu như không hoạt động — card Wi-Fi thường mất điện hẳn khi máy ngủ. Script giờ **ưu tiên card Ethernet** nếu có, và nếu chỉ có Wi-Fi thì báo thẳng đây là vật cản. Nếu chỉ viết theo lý thuyết thì mục này đã không tồn tại.
2. **`Get-NetAdapterPowerManagement` lỗi trên card Wi-Fi này** ("A device attached to the system is not functioning"), và `Get-BitLockerVolume` đòi quyền admin. Cả hai đều ghi lỗi ra stderr nhưng script vẫn cho JSON đầy đủ — nên code **cố tình parse stdout bất kể exit code**, vì vứt đi là mất luôn địa chỉ MAC.

Kết quả thật của máy này: `Wi-Fi`, MAC `84:9E:...`, broadcast `192.168.1.255`, **Fast Startup đang bật**, ARSO không bị chính sách chặn. Hai vật cản có thật đang chờ xử lý: Wi-Fi và Fast Startup.

- **Một lỗi do test bắt được.** `RawDatagramSocket.send` trả về 0 thay vì ném lỗi khi socket chưa sẵn sàng ghi, và socket vừa bind thường xuyên như vậy ở lần gửi đầu. Bản đầu tin vào số 0 đó nên âm thầm mất gói rồi báo máy không phản hồi vì lý do chẳng liên quan. Giờ có retry.
- **Kiểm chứng:** 456 test Flutter và 35 test relay đều qua. Test đánh thức chạy lặp ba lần để chắc không flaky. Test chẩn đoán dùng **output thật lấy từ máy này**, không phải dữ liệu bịa.
- **Chưa kiểm chứng:** chưa đánh thức được một máy thật, vì máy khảo sát chỉ có Wi-Fi. Cần một máy nối dây mới xác nhận được đường đi đầu-cuối.

## Tiến độ Phase 1

- **RMC-004 xong.** `MachineShutdownService` (19 dòng) thành `MachinePowerService`: tắt, khởi động lại, ngủ, ngủ đông, khóa, sign out, huỷ. Không bao giờ tự thêm `/f`. Khởi động lại dùng `shutdown /g` để Windows đăng nhập lại và mở lại app. Đọc `powercfg /a` để biết máy có S3 thật không, và nếu "Ngủ" thực chất sẽ ngủ đông thì nhãn trên điện thoại đổi theo.
- **RMC-005 xong.** Có `_controlPollLoop()` chạy song song, long-poll `desktop/control-commands`, **không** kiểm tra `_runner.isBusy`. Quy tắc an toàn tách thành hàm thuần `powerCommandRejection(...)` nên test được không cần mạng: khóa và huỷ luôn đi qua kể cả đang build; tắt/khởi động lại/ngủ/ngủ đông/sign out bị chặn khi đang build trừ khi điện thoại chủ động chọn "vẫn làm".
- **RMC-006 xong.** Relay nhận loại `power`, chuẩn hoá payload, chặn action lạ, kẹp `delaySeconds` ở 600. Lệnh mang `lane` và hai hàng đợi tách hẳn nhau. Phần bắt buộc `targetDesktopId` từ Phase 0 giờ **đã có test thật**.
- **RMC-007 xong.** `MobileControlView` thành hai tab Máy tính / Chạy. Tab Máy tính có card trạng thái, bốn nút nguồn, xác nhận hai bước và đếm ngược 15 giây có nút huỷ. Máy offline hoặc chưa bật quyền thì nút mờ kèm lý do, không để người dùng bấm rồi mới biết hỏng.
- **RMC-008 xong.** Máy tính hiện banner đỏ đếm ngược, đặt cuối Stack nên không gì che được nút **Huỷ ngay** — người ngồi trước máy luôn ưu tiên hơn người cầm điện thoại. Mọi lệnh nguồn ghi vào log hệ thống.
- **RMC-019 xong.** `WindowsAutoStartService` quản shortcut trong thư mục Startup, trạng thái đọc thẳng từ file chứ không qua preference. `install.ps1` tạo sẵn, `uninstall.ps1` dọn đi. Có công tắc trong Options.
- **RMC-020 xong.** Heartbeat báo `sessionLocked`, `powerControlEnabled`, `sleepSupport`. Điện thoại hiện ba trạng thái **Đang mở / Đang khóa / Offline**. `powercfg /a` chỉ đọc một lần rồi cache, không spawn process mỗi 10 giây.
- **Kiểm chứng:** 439 test Flutter và 35 test relay đều qua. Test autostart có một ca chạy PowerShell thật và kiểm tra file `.lnk` sinh ra — script trông đúng mà không tạo được shortcut thì ca đó sẽ đỏ.
- **Chưa kiểm chứng:** chưa chạy đầu-cuối với relay thật trên máy thật. Cụ thể chưa xác nhận `shutdown /g` + ARSO có thực sự đưa agent sống lại trên máy có PIN — mục 4.6 nói rõ việc này phụ thuộc phiên bản Windows và chính sách máy. Đây là hạng mục đầu tiên của kiểm thử thủ công ở mục 7.

## Tiến độ Phase 0

- **RMC-001 xong.** Control token của điện thoại chuyển sang `flutter_secure_storage` qua `MobileControlCredentialStoreService`. `MobileControlSettings.toJson` không còn ghi token, nên mỗi lần lưu là một lần dọn. Bản cũ để token trong SharedPreferences thì lần chạy đầu sẽ chuyển nó sang kho bảo mật rồi xoá khỏi preferences. `RemoteControlService` có `init()` async và được đăng ký bằng `Get.putAsync` để điện thoại không chớp qua màn hình ghép nối khi đã liên kết sẵn.
- **RMC-002 xong phần thực thi được.** Relay gắn scope (`run` / `power` / `window`) cho pairing do máy tính tạo, rồi chép sang thiết bị lúc ghép — điện thoại tự xin scope thì bị bỏ qua. Lệnh sai scope trả 403. Thiết bị và pairing tạo trước thay đổi này mặc định về `run`, nên bản cũ không vỡ. Phần bắt buộc `targetDesktopId` đã viết nhưng **chưa kiểm chứng được**: nó chỉ áp cho `power` / `window` / `app`, mà whitelist còn chặn các loại đó — test sẽ đi cùng RMC-006.
- **RMC-003 xong.** `RemoteControlSettings` có `allowPowerControl`, `allowWindowControl`, `allowedApps`, tất cả mặc định tắt và giữ nguyên trạng thái tắt với settings lưu từ trước. Options > Điều khiển có hai công tắc và dialog Ứng dụng cho phép. Scope của pairing lấy theo đúng hai công tắc này tại thời điểm ghép.
- **Kiểm chứng:** 399 test Flutter và 29 test relay đều qua (thêm 9 test Dart và 5 test relay). `flutter analyze` không phát sinh cảnh báo mới. Chưa chạy thử trên máy thật với relay thật — phần đó thuộc kiểm thử thủ công ở mục 7.
- **Lưu ý triển khai:** `serverless/notifications` là repo git riêng, phải commit và deploy tách khỏi repo app. Thứ tự deploy nào trước cũng an toàn: relay mới với app cũ thì pairing về `run` mặc định; app mới với relay cũ thì trường `scopes` bị bỏ qua.

Luồng remote mobile hiện tại đã chạy được đầu-cuối cho **release automation**: điện thoại ghép với relay, thấy dự án, chạy script/Fastlane/shell, gửi stdin, xem log, dừng lệnh. Nhưng nó chỉ điều khiển *tiến trình build*, chưa điều khiển *cái máy*. Kế hoạch này mở rộng sang điều khiển nguồn máy (tắt / khởi động lại / ngủ / khóa / đánh thức) và điều khiển cửa sổ, ứng dụng — đồng thời lấp các khoảng trống đang làm luồng remote hiện có chưa hoàn chỉnh.

## 1. Mục tiêu và phạm vi

Từ điện thoại Android, với máy Windows cá nhân đã ghép:

- **Tắt nguồn**: shutdown, restart, sign out, sleep, khóa màn hình, và hủy lệnh đang đếm ngược.
- **Bật nguồn**: đánh thức máy bằng Wake-on-LAN khi điện thoại ở cùng mạng nhà.
- **Cửa sổ và ứng dụng**: liệt kê cửa sổ đang mở, đưa lên trước, thu nhỏ, đóng; mở/đóng ứng dụng trong danh sách cho phép.
- **Hoàn thiện phần đang dở**: chọn máy khi có nhiều desktop, lịch sử lệnh, ghép bằng QR, và siết bảo mật trước khi trao quyền nguồn.

Ngoài phạm vi bản này: điều khiển chuột/bàn phím và stream màn hình (việc đó thuộc RDP/Parsec, không nên tự dựng), iOS, và đánh thức máy qua Internet mà không có thiết bị nào trong LAN. Đây là lựa chọn phạm vi đề xuất để bản đầu gọn, không phải giới hạn kỹ thuật.

**Mặc định an toàn.** Mọi quyền mới đều tắt sẵn. Máy tính là nơi bật quyền, điện thoại chỉ là nơi dùng quyền đã được bật.

## 2. Hiện trạng đã kiểm tra

| Thành phần | Hiện trạng | Hướng xử lý |
|---|---|---|
| `lib/app/services/remote_control_service.dart` | 784 dòng. Heartbeat 10s, long-poll lệnh 20s, claim, publish trạng thái 2s, poll stdin 1s | Thêm lane điều khiển song song, không đụng lane release |
| `RemoteControlService._desktopPollLoop` | Chờ khi `_runner.isBusy` hoặc đang chạy lệnh từ xa | Nút thắt: lệnh nguồn sẽ kẹt trong hàng đợi lúc đang build — xem mục 4.2 |
| `lib/app/models/remote_control.dart` | 4 model: settings desktop/mobile, `RemoteDesktopState`, `RemoteCommand` | Thêm capability, danh sách máy, model cửa sổ |
| `serverless/notifications/src/app.js:589` | Whitelist cứng `["shell", "script", "fastlane"]` | Mở rộng loại lệnh kèm chuẩn hóa payload riêng |
| `GET /api/mobile/desktop-state` | Trả `listDesktopStates()[0]` — chỉ máy nào heartbeat gần nhất | Thêm endpoint danh sách; mobile chọn máy |
| `RemoteCommand.targetDesktopId` | Mobile không bao giờ gửi, relay mặc định `"default"` | Bắt buộc với lệnh nguồn: không được tắt nhầm máy |
| `lib/app/services/machine_shutdown_service.dart` | 19 dòng, chỉ `shutdown.exe /s /t 0`, chỉ phục vụ "shutdown sau khi deploy" | Mở rộng thành service nguồn đầy đủ |
| `lib/app/views/mobile_control_view.dart` | 685 dòng. Ghép nối gõ tay endpoint + mã + pairing id; refresh 3s; giữ đúng **một** `activeMobileCommand` | Thêm tab Máy tính; lưu lịch sử lệnh |
| `ProjectStoreService` khóa `mobile_control_settings` | Control token lưu SharedPreferences dạng thô | Chuyển sang `flutter_secure_storage` (đã có sẵn dependency) |
| `requireMobileAuth` trong relay | Bất kỳ device đã ghép nào cũng gửi được mọi loại lệnh | Thêm scope theo thiết bị |
| `android/app/src/main/AndroidManifest.xml` | Chỉ `INTERNET`; không FCM, không foreground service | Đủ cho WoL (UDP broadcast); push là mở rộng |
| `pubspec.yaml` | Có `qr_flutter` (chỉ sinh mã, không quét) | Quét QR cần thêm dependency — xem RMC-016 |

### Khoảng trống chặn mục tiêu

1. Không có loại lệnh nào chạm tới nguồn máy hay cửa sổ.
2. Lane lệnh bị chặn bởi `_runner.isBusy`: gửi "khóa máy" lúc đang build thì lệnh nằm chờ đến khi build xong — đúng lúc người dùng cần nó nhất thì nó không chạy.
3. Bật máy từ xa **không thể làm bằng agent**: máy tắt thì agent cũng tắt. Đây là ràng buộc vật lý, không phải thiếu code — xem mục 4.3.
4. Mobile không chọn được máy, và lệnh không ghi rõ máy đích.
5. Đóng app là mất dấu lệnh đang chạy; không có lịch sử.
6. Token điều khiển lưu thô, không hạn dùng, không thu hồi được từ điện thoại.

## 3. Trải nghiệm sản phẩm

`MobileControlView` chuyển từ một trang cuộn dài sang ba tab: **Máy tính**, **Chạy** (nguyên trạng), **Cửa sổ**.

### Tab Máy tính

- Card máy trên cùng: tên, trạng thái online, đang chạy gì, thời điểm heartbeat cuối. Có nhiều máy thì đây là nơi chọn máy, và lựa chọn được nhớ lại.
- Hàng nút nguồn: **Khóa** · **Ngủ** · **Khởi động lại** · **Tắt máy**. Máy offline thì cả hàng mờ đi, trừ **Đánh thức**.
- **Tắt máy** và **Khởi động lại** phải xác nhận hai bước, sau đó vào trạng thái đếm ngược 15 giây với nút **Hủy** to — trên cả điện thoại lẫn màn hình máy tính. Hủy gọi `shutdown /a`.
- Đang chạy release thì nút nguồn hiện cảnh báo đỏ kèm tên script và không cho bấm tiếp trừ khi người dùng chủ động chọn "vẫn tắt".
- **Đánh thức** chỉ hiện khi máy đã lưu địa chỉ MAC. Bấm xong hiện "Đang gửi tín hiệu…" và chờ heartbeat trong 90 giây; quá hạn thì mở bảng tự chẩn đoán (mục 4.3) chứ không chỉ báo lỗi cộc lốc.

### Tab Cửa sổ

- Danh sách cửa sổ đang mở: tên tiến trình, tiêu đề cửa sổ. Mỗi dòng có **Đưa lên trước**, **Thu nhỏ**, **Đóng**.
- Đóng dùng đóng mềm (`CloseMainWindow`), nên ứng dụng vẫn kịp hỏi lưu file. Không có "kill" trong bản đầu.
- Dưới cùng là các ứng dụng đã ghim sẵn trên máy tính: bấm để mở. Điện thoại không gửi đường dẫn — chỉ gửi khóa trong danh sách cho phép.
- Danh sách cửa sổ làm mới theo yêu cầu và mỗi 10 giây khi tab đang mở, không poll liên tục (mục 4.4).

## 4. Thiết kế kỹ thuật

### 4.1 Loại lệnh mới

Giữ nguyên cấu trúc `RemoteCommand`, thêm ba loại vào whitelist của relay:

| Loại | Payload | Ghi chú |
|---|---|---|
| `power` | `{action, delaySeconds, force}` với action thuộc `shutdown / restart / sleep / lock / logoff / hibernate / cancel` | `force` mặc định `false`; relay bắt buộc `targetDesktopId` |
| `window` | `{action, windowId}` với action thuộc `list / focus / minimize / close` | `windowId` là handle do chính máy tính phát ra ở lần `list` gần nhất |
| `app` | `{action, appKey}` với action thuộc `launch / close` | `appKey` tra trong allowlist của máy; **không nhận path từ điện thoại** |

Lệnh `power` và `window` không đi qua `ReleaseRunnerService` — chúng không có log stream, không có stdin, và phải trả kết quả trong vài giây.

### 4.2 Lane điều khiển song song

Đây là thay đổi kiến trúc chính. Tách `_controlPollLoop()` chạy độc lập với `_desktopPollLoop()`:

- Long-poll `GET /api/desktop/control-commands?desktopId=&waitMs=` — hàng đợi riêng, chỉ nhận `power` / `window` / `app`.
- Không kiểm tra `_runner.isBusy`, không đặt cờ `_isExecutingRemoteCommand`, nên release đang chạy không chặn được nó.
- Thực thi trực tiếp qua service nguồn/cửa sổ rồi `POST .../events` một lần với kết quả. Không có publish định kỳ 2 giây.
- Ngược lại, lane điều khiển **phải** đọc trạng thái của runner để từ chối lệnh nguy hiểm: `shutdown` khi `_runner.isBusy` và `force != true` thì trả `failed` kèm lý do để điện thoại hiện cảnh báo, thay vì âm thầm tắt máy giữa lúc upload bundle.

Bên relay, hàng đợi điều khiển dùng lại `store.listRemoteCommands` nhưng lọc theo `lane: "control"` gắn lúc tạo lệnh — không cần bảng mới, cả `store.js` lẫn `firestore_store.js` đều chỉ thêm một tham số lọc.

### 4.3 Bật máy: ràng buộc thật và đường đi

Máy đã tắt thì không có gì trên máy để nhận lệnh. Relay trên cloud **không** tự đánh thức được máy ở nhà: magic packet là gói broadcast trong mạng LAN, không định tuyến qua Internet. Ba đường khả dĩ:

| Đường | Cách làm | Đánh giá |
|---|---|---|
| **A. Điện thoại gửi WoL khi ở nhà** | App gửi UDP magic packet tới broadcast của subnet, cổng 9 | Không thêm hạ tầng, không thêm dependency. **Chọn cho bản đầu** |
| B. Thiết bị luôn bật trong LAN chuyển tiếp | Một máy/Pi/router lấy "wake intent" từ relay rồi phát WoL | Đánh thức được từ ngoài nhà, nhưng cần thêm phần cứng và một agent nữa |
| C. Ổ cắm thông minh + BIOS "Restore on AC Power Loss" | Ngoài phần mềm | Chỉ nên ghi vào tài liệu như phương án dự phòng |

Magic packet: 6 byte `0xFF` rồi lặp 16 lần địa chỉ MAC, tổng 102 byte, gửi UDP qua `RawDatagramSocket` với `broadcastEnabled = true` tới cả `255.255.255.255` lẫn địa chỉ broadcast của subnet đã lưu. Android không cần quyền nào ngoài `INTERNET` cho việc này.

Phần khó không nằm ở gói tin mà ở cấu hình máy, nên máy tính phải **tự khai báo mức sẵn sàng** trong heartbeat, để điện thoại chẩn đoán được thay vì đoán mò:

- MAC và địa chỉ broadcast của card mạng đang dùng.
- `powercfg /a` — máy có hỗ trợ S3/S4 hay chỉ có Modern Standby.
- Fast Startup (`HiberbootEnabled`): đang bật thì WoL từ trạng thái tắt hẳn rất hay thất bại.
- `Get-NetAdapterPowerManagement` — card mạng có bật "Wake on Magic Packet" không.

Với nhiều card mạng phổ thông, đánh thức từ S5 (tắt hẳn) không hoạt động dù cấu hình đúng, chỉ S3/S4 mới chắc chắn. Tài liệu phải nói thẳng điều này: "Đánh thức" là để dựng máy dậy từ ngủ/ngủ đông, còn bật máy từ trạng thái tắt hẳn là *có thể*, không phải *chắc chắn*.

### 4.4 Điều khiển nguồn và cửa sổ trên Windows

Mở rộng `MachineShutdownService` thành `MachinePowerService`, vẫn gọi tiến trình hệ thống, không thêm dependency:

| Hành động | Lệnh |
|---|---|
| Tắt máy | `shutdown.exe /s /t <delay>` — giữ mặc định **không** `/f` để không giết việc chưa lưu |
| Khởi động lại | `shutdown.exe /r /t <delay>` |
| Sign out | `shutdown.exe /l` |
| Hủy lệnh chờ | `shutdown.exe /a` |
| Khóa màn hình | `rundll32.exe user32.dll,LockWorkStation` |
| Ngủ | PowerShell gọi `System.Windows.Forms.Application.SetSuspendState(PowerState.Suspend, false, false)` |
| Ngủ đông | `shutdown.exe /h` |

"Ngủ" và "Ngủ đông" là hai action riêng. Lệnh Sleep dùng API có kiểu dữ liệu rõ ràng và giữ wake events hoạt động để Wake-on-LAN có thể đánh thức máy; giao diện chỉ bật từng nút khi `powercfg /a` báo trạng thái đó được hỗ trợ.

`MachineShutdownService` hiện được dùng ở `home_controller.dart` và giả lập trong `test/home_controller_telegram_release_test.dart`. Đổi tên là ba chỗ sửa, làm luôn trong RMC-004 thay vì để lại một facade thừa.

Cửa sổ thì Dart thuần không làm được. Dùng PowerShell, không thêm dependency:

- Liệt kê: `Get-Process | Where-Object MainWindowHandle -ne 0` cho ra handle, tên tiến trình, tiêu đề.
- Đóng mềm: `(Get-Process -Id <id>).CloseMainWindow()`.
- Đưa lên trước / thu nhỏ: `Add-Type` khai báo `ShowWindow` và `SetForegroundWindow` của `user32.dll`.

Mỗi lần gọi PowerShell tốn khoảng 200–400 ms khởi động, nên đây là lý do tab Cửa sổ làm mới theo chu kỳ 10 giây chứ không stream. Nếu độ trễ thành vấn đề thì chuyển sang `dart:ffi` với `package:win32`, nhưng chỉ khi đo được, không làm trước.

### 4.5 Bảo mật — điều kiện bắt buộc trước khi mở quyền nguồn

Hôm nay một token bị lộ nghĩa là kẻ khác chạy được shell trong thư mục dự án. Sau kế hoạch này, nó nghĩa là kẻ khác tắt được máy và đóng được ứng dụng đang có việc dở. Phase 0 phải xong trước Phase 1:

- **Scope thiết bị.** Lúc ghép, relay gắn `scopes` cho device (`run`, `power`, `window`). Lệnh ngoài scope trả 403. Thiết bị đã ghép từ trước mặc định chỉ có `run`.
- **Cờ cho phép trên máy tính.** `RemoteControlSettings` thêm `allowPowerControl`, `allowWindowControl`, `allowedApps`, tất cả mặc định tắt. Máy tính từ chối lệnh cả khi relay đã cho qua — hai lớp, không chỉ một.
- **Token vào secure storage.** Chuyển `mobile_control_settings` khỏi SharedPreferences sang `flutter_secure_storage`, kèm di trú bản cũ như `LegacyStorageMigrationService` đã làm.
- **Máy đích tường minh.** Lệnh `power` không có `targetDesktopId` thì relay trả 400.
- **Dấu vết.** Mọi lệnh nguồn ghi vào log hệ thống của máy và hiện lớp đếm ngược ngay trên màn hình máy tính — người đang ngồi trước máy luôn hủy được.

### 4.6 Máy có mã PIN — và agent không tự khởi động

Đây là ràng buộc lớn nhất của cả Phase 1 lẫn Phase 2, và nó có **hai cổng chắn** chứ không phải một.

**Cổng thứ nhất: app không tự chạy.** `installer/windows/install.ps1` chỉ tạo shortcut Start Menu và Desktop — không có mục nào trong Startup hay `Run` registry. Nên hôm nay, sau mỗi lần khởi động lại máy, agent nằm im cho tới khi có người tự tay mở app. Bất kỳ kịch bản "khởi động lại rồi điều khiển tiếp" nào cũng hỏng ngay tại đây, độc lập với mã PIN.

**Cổng thứ hai: mã PIN chắn ở màn hình đăng nhập.** App là ứng dụng người dùng, chạy trong session của người đăng nhập. Chưa đăng nhập thì chưa có session, chưa có app, chưa có heartbeat.

Hệ quả khác hẳn nhau tùy hành động:

| Hành động | Mã PIN ảnh hưởng gì | Kết luận |
|---|---|---|
| **Khóa màn hình** | Session vẫn sống, app vẫn chạy, heartbeat vẫn gửi | Chạy tốt. Khóa xong vẫn chạy được release từ điện thoại |
| **Ngủ / ngủ đông rồi đánh thức** | Session được khôi phục nguyên vẹn, máy dừng ở màn hình khóa nhưng app chưa bao giờ tắt | Chạy tốt. Đây là lý do nên coi ngủ là đường chính |
| **Khởi động lại** | Session mất. Cần đăng nhập lại mới có app | Cần cấu hình thêm — xem dưới |
| **Tắt hẳn rồi WoL** | Vừa mất session vừa mất cả cổng thứ nhất | Cần cấu hình thêm, và là trường hợp khó nhất |
| **BitLocker có PIN trước khi khởi động** | Máy dừng trước cả Windows | Không thể làm từ xa |

Ba mức xử lý, chọn theo mức độ đánh đổi mà người dùng chấp nhận:

1. **Bắt buộc, làm trong Phase 1: cho app tự khởi động cùng Windows.** Thêm shortcut vào thư mục Startup trong `install.ps1`, kèm một công tắc trong Options để bật/tắt. Việc này gỡ cổng thứ nhất và tự nó đã làm "khởi động lại từ xa" khả dụng với máy không đặt PIN.
2. **Cho khởi động lại: dùng `shutdown /g` thay vì `/r`.** `/g` yêu cầu Windows đăng nhập lại và mở lại ứng dụng đã đăng ký sau khi khởi động, dựa trên Automatic Restart Sign-On — cần bật "Dùng thông tin đăng nhập để tự động hoàn tất thiết lập sau khi cập nhật hoặc khởi động lại" trong Sign-in options. Windows sẽ tự đăng nhập rồi khóa màn hình ngay, nên session sống lại mà không ai phải gõ PIN. Cơ chế này phụ thuộc phiên bản Windows và chính sách của máy, nên RMC-009 phải **đọc trạng thái thật rồi báo về điện thoại**, không được giả định là có.
3. **Cho tắt hẳn rồi WoL: cần tự đăng nhập.** Không có tự đăng nhập thì WoL chỉ bật được phần cứng — máy sáng đèn, dừng ở màn hình khóa, và điện thoại vẫn thấy "offline" vì không có gì gửi heartbeat. Hai đường: bật tự đăng nhập rồi khóa ngay (nên dùng Autologon của Sysinternals vì nó cất mật khẩu trong LSA secret thay vì để thô trong registry), hoặc viết một Windows service nhỏ chạy trước đăng nhập chỉ để heartbeat và nhận lệnh nguồn. Service thì an toàn hơn nhưng là một agent thứ hai phải nuôi, và Session 0 không điều khiển được cửa sổ — để dành, không làm trong bản này.

Với BitLocker có PIN trước khi khởi động thì không có đường phần mềm nào. Trường hợp duy nhất cứu được là một lần khởi động lại có kế hoạch: `manage-bde -protectors -disable -rebootcount 1` cho phép đúng một lần bỏ qua, rồi tự bật lại. Chỉ nên ghi vào tài liệu, không tự động hóa.

**Tác động lên UI.** Heartbeat phải báo thêm `sessionLocked`, và điện thoại hiện ba trạng thái chứ không phải hai: **Đang mở** · **Đang khóa** · **Offline**. "Đang khóa" vẫn chạy được mọi lệnh — người dùng cần biết điều đó thay vì tưởng máy đã tắt.

## 5. Hợp đồng relay

| Endpoint | Thay đổi |
|---|---|
| `POST /api/mobile/commands` | Whitelist thêm `power`, `window`, `app`; chuẩn hóa payload riêng; kiểm tra scope; bắt buộc `targetDesktopId` cho `power` |
| `GET /api/mobile/desktops` | **Mới.** Danh sách máy thay cho việc chỉ trả phần tử đầu |
| `GET /api/desktop/control-commands` | **Mới.** Long-poll lane điều khiển |
| `POST /api/desktop/heartbeat` | `state` thêm `capabilities`: khả năng nguồn, cửa sổ, và chẩn đoán WoL |
| `POST /api/control-devices` | Nhận và lưu `scopes` khi ghép |

`GET /api/mobile/desktop-state` giữ nguyên để bản app cũ không vỡ.

## 6. Danh sách ticket

**Phase 0 — nền tảng an toàn** (bắt buộc trước Phase 1)

| Mã | Việc | Kích cỡ |
|---|---|---|
| RMC-001 | Chuyển control token sang secure storage, kèm di trú | S |
| RMC-002 | Scope thiết bị ở relay + bắt buộc `targetDesktopId` cho lệnh nguồn | M |
| RMC-003 | Cờ `allowPowerControl` / `allowWindowControl` / `allowedApps` + UI trong Options > Điều khiển | M |

**Phase 1 — điều khiển nguồn**

| Mã | Việc | Kích cỡ |
|---|---|---|
| RMC-004 | `MachinePowerService` đầy đủ hành động + đọc `powercfg /a`; khởi động lại dùng `shutdown /g`; đổi tên tại 3 call site | M |
| RMC-005 | Lane điều khiển song song ở service và relay, không bị `_runner.isBusy` chặn | L |
| RMC-006 | Whitelist + chuẩn hóa payload `power` ở relay, kèm test | S |
| RMC-007 | Tab Máy tính trên mobile: card, nút nguồn, xác nhận hai bước, đếm ngược hủy | M |
| RMC-008 | Lớp đếm ngược và ghi log trên màn hình máy tính | S |
| RMC-019 | App tự khởi động cùng Windows: mục Startup trong `install.ps1` + công tắc trong Options | M |
| RMC-020 | Heartbeat báo `sessionLocked`; điện thoại hiện ba trạng thái Mở / Khóa / Offline | S |

**Phase 2 — đánh thức máy**

| Mã | Việc | Kích cỡ |
|---|---|---|
| RMC-009 | Heartbeat khai báo chẩn đoán WoL (MAC, broadcast, sleep state, Fast Startup, NIC) **và trạng thái đăng nhập lại**: app có trong Startup không, ARSO có bật không, BitLocker có PIN trước khởi động không | M |
| RMC-010 | Gửi magic packet từ điện thoại + nút Đánh thức + chờ heartbeat 90s | M |
| RMC-011 | Bảng tự chẩn đoán khi đánh thức thất bại + tài liệu cấu hình BIOS/NIC | S |

**Phase 3 — cửa sổ và ứng dụng**

| Mã | Việc | Kích cỡ |
|---|---|---|
| RMC-012 | `WindowControlService` qua PowerShell: list / focus / minimize / close | L |
| RMC-013 | Allowlist ứng dụng trên máy + lệnh `app` mở/đóng theo khóa | M |
| RMC-014 | Tab Cửa sổ trên mobile | M |

**Phase 4 — hoàn thiện luồng remote hiện có**

| Mã | Việc | Kích cỡ |
|---|---|---|
| RMC-015 | Chọn máy khi có nhiều desktop, nhớ lựa chọn | M |
| RMC-016 | Ghép nối bằng quét QR (desktop đã sinh sẵn mã) | M |
| RMC-017 | Lịch sử lệnh trên mobile, khôi phục lệnh đang chạy sau khi mở lại app | M |
| RMC-018 | Nhận trạng thái khi app đóng — FCM hoặc foreground service | L |

RMC-018 là mở rộng, không thuộc định nghĩa "hoàn chỉnh" của bản này.

## 7. Kiểm thử

- **Dart unit.** `MachinePowerService` với process runner giả lập: đúng lệnh, đúng tham số, `/f` không tự xuất hiện. Lane điều khiển với `ReleaseCenterConnect` giả lập: lệnh nguồn vẫn chạy khi runner báo bận; `shutdown` không `force` bị từ chối khi đang build. Byte của magic packet: 102 byte, đúng cấu trúc.
- **Widget.** Tab Máy tính: máy offline thì nút nguồn tắt; xác nhận hai bước; hủy trong lúc đếm ngược; cảnh báo khi đang chạy release. Theo mẫu `test/mobile_control_view_test.dart` hiện có.
- **Relay.** Bổ sung `serverless/notifications/test/app.test.js`: loại lệnh mới, 403 khi ngoài scope, 400 khi thiếu `targetDesktopId`, lane điều khiển không trả lệnh release.
- **Thủ công, phải làm trên máy thật.** Khóa màn hình; ngủ rồi đánh thức bằng điện thoại; tắt máy có đếm ngược và hủy giữa chừng; tắt máy trong lúc đang build (phải bị chặn); đánh thức từ S5 sau khi tắt Fast Startup (ghi lại kết quả thật của card mạng đang dùng); đóng cửa sổ có file chưa lưu (ứng dụng phải kịp hỏi).

## 8. Rủi ro

| Rủi ro | Xử lý |
|---|---|
| WoL từ trạng thái tắt hẳn không chạy trên card mạng đang dùng | Nói rõ trong tài liệu và bảng chẩn đoán; coi ngủ/ngủ đông là đường chính |
| Máy có PIN: khởi động lại xong agent không sống lại | RMC-019 cho app tự khởi động; `shutdown /g` + ARSO; RMC-009 báo trước tình trạng thay vì để người dùng phát hiện lúc máy đã tắt |
| BitLocker có PIN trước khởi động chặn mọi thứ | Không tự động hóa; ghi vào tài liệu và cho bảng chẩn đoán cảnh báo sớm |
| Ra khỏi nhà là không đánh thức được | Ghi rõ trong UI; đường B (thiết bị chuyển tiếp) để dành cho sau |
| Tắt máy giữa lúc upload bundle làm hỏng artifact | Chặn mặc định khi runner bận; muốn tắt phải chủ động chọn |
| Token bị lộ = toàn quyền máy | Phase 0 chặn trước Phase 1: scope, secure storage, cờ trên máy |
| Android tối ưu pin giết vòng poll | Chấp nhận trong bản đầu — app đang mở mới điều khiển; RMC-018 mới giải quyết |
| PowerShell chậm khi liệt kê cửa sổ | Làm mới 10 giây thay vì stream; đo trước khi nghĩ tới FFI |
| Đổi tên `MachineShutdownService` làm vỡ test | Chỉ 3 call site, sửa trong cùng ticket |

## 9. Thứ tự đề xuất

Phase 0 rồi Phase 1 cho ra giá trị lớn nhất với rủi ro thấp nhất: tắt, khởi động lại, ngủ, khóa từ điện thoại, có chặn đúng lúc đang build. Phase 2 phụ thuộc phần cứng nên tách riêng để không chặn Phase 1. Phase 3 độc lập, làm được bất cứ lúc nào sau Phase 0. Phase 4 là dọn nợ của luồng cũ, xen vào giữa các phase khi có chỗ.
