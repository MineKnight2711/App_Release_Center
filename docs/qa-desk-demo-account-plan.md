# Kế hoạch: tài khoản demo và kịch bản tự thao tác trong QA Desk

Ngày: 2026-10-02. Trạng thái: **Đã triển khai Phase A–D** (xem [Tiến độ](#10-tiến-độ)); còn chạy thật bằng demo account và deploy Firestore rules. Làm tiếp trên nhánh `feature/qa-desk-module`, sau Phase 0–3 của [qa-desk-integration-plan.md](qa-desk-integration-plan.md).

Team cấp demo account **một lần**. QA Desk dùng nó để **tự đăng nhập và thao tác trên app thật** (máy ảo hoặc điện thoại Android, trình duyệt với app web), kiểm tra màn hình và báo lỗi kèm ảnh chụp; dự án không cần viết code test.

Tóm tắt:

- **Công cụ thao tác: Maestro.** Kịch bản viết bằng YAML, không cần sửa app, chạy được Android, Flutter và web, cài native trên Windows. QA Desk lo phần còn lại: soạn kịch bản không cần code, giữ tài khoản, chặn rủi ro production, đọc kết quả.
- **Tài khoản nằm trong kho chung của team** (Firebase), mã hoá đầu-cuối bằng passphrase của team. Firebase chỉ giữ bản mã. Mỗi lần chạy "mượn" một tài khoản, nên hai người không đăng nhập đè nhau.
- **Áp dụng cho mọi app:** mỗi app được mô tả bằng cấu hình trong repo của nó (gói/URL, bản build theo môi trường, flow đăng nhập). Không có code riêng cho FizaHUB.
- **Staging và production:** mỗi kịch bản tự khai là *đọc* hay *ghi*. Kịch bản ghi chỉ chạy được trên staging. Production có ba lớp chặn, và tài khoản production luôn là chỉ đọc.

## 1. Quyết định đã chốt

| Câu hỏi | Trả lời |
|---|---|
| Demo account dùng để làm gì | QA Desk tự thao tác trên app; không cần viết test trong dự án |
| Lưu ở đâu | Chia sẻ theo team |
| Được làm gì với dữ liệu | Cả staging và production; kịch bản tự khai đọc hay ghi |
| Cho app nào | Mọi app được setup về sau |

Ngoài phạm vi:
- **iOS:** cần macOS, mà AMC chạy trên Windows.
- **AI tự khám phá app:** không chọn ở lượt này.
- **Đăng nhập không tự động hoá được:** CCCD gắn chip, VNeID, sinh trắc, OTP gửi qua SMS. OTP dạng TOTP thì có thể làm ở Phase E.
- **App desktop.**

## 2. Hiện trạng đã kiểm tra

| Thành phần | Hiện trạng | Ý nghĩa với plan |
|---|---|---|
| `fizahub_app` đăng nhập | Số điện thoại + mật khẩu, gọi API với `dt`/`pass`, không OTP. Màn đăng nhập có `Key('phoneField')`, `Key('passwordField')` và hint "Nhập số điện thoại của bạn" | Tự động hoá được. Maestro **không thấy Flutter Key**, chỉ thấy Semantics và chữ hiển thị, nên bắt đầu bằng chọn theo hint text; nên thêm `Semantics(identifier: …)` để bền hơn |
| Test giao diện của app | Không có `integration_test`, Patrol, Maestro hay Appium flow | Chưa có gì để dùng lại; QA Desk tự thao tác là phần mới hoàn toàn |
| Catalog `fizahub_app` | Môi trường Staging khai secret `TEST_USERNAME`, `TEST_PASSWORD`, nhưng chưa test nào đọc | Nhu cầu đã có từ trước; mô hình secret theo phiên hiện tại bắt nhập lại mỗi lần mở AMC |
| Secret của QA Desk | Chỉ trong bộ nhớ, đưa vào suite qua biến môi trường, **không bị che trong log** | Phải che giá trị trong log, lịch sử và báo cáo trước khi dùng mật khẩu thật |
| Chạy tiến trình | `SafeProcessRunner` chỉ cho phép `flutter, dart, node, npm, npx, adb, appium` | Thêm `maestro`, lấy từ thư mục cài do QA Desk quản lý |
| Thiết bị | Có `DeviceRunLock` dùng chung với Kiểm tra AAB; Kiểm tra AAB cài được AAB lên máy ảo bằng `bundletool --connected-device` | Dùng lại cho bước cài đúng bản build trước khi chạy |
| Tải công cụ | `BundletoolManager` ghim phiên bản và kiểm SHA-256 trước khi dùng | Cùng cách đó cho Maestro |
| Team AMC | Firebase Auth, `teams/{id}/members` với vai trò `admin`/`dev`; API Tool lưu theo team ở `teams/{id}/apiTool…` | Thêm collection `qaAccounts`, `qaAccountLeases`, `qaAccountAudit` theo cùng mẫu |
| Mã hoá | `ResourceCatalogCryptoService` dùng AES-GCM 256, payload có phiên bản | Dùng lại thuật toán; khoá lấy từ passphrase của team thay vì khoá máy |
| Máy này | Java 21, Android SDK; chưa có Maestro | Đủ điều kiện chạy Maestro (cần Java ≥ 17) |

## 3. Chọn công cụ thao tác

| | Maestro | Appium (đã quản lý trong QA Desk) | Patrol / integration_test | adb thuần |
|---|---|---|---|---|
| App bất kỳ (native, Flutter, RN, web) | Có | Android có, web cần driver riêng | Chỉ Flutter | Chỉ Android |
| Không cần sửa code app | Có (Flutter nên thêm Semantics) | Có | **Không**: test nằm trong repo app | Có |
| Chờ, thử lại, độ ổn định | Có sẵn | Phải tự viết | Tốt | Phải tự viết, dễ chập chờn |
| Định dạng kịch bản | YAML, đọc được, QA Desk sinh ra được | Code gọi WebDriver | Dart | Tự định nghĩa |
| Trên Windows | Native (zip, Java 17+) | Có | Có | Có |

**Đề xuất: Maestro.** Kịch bản do QA Desk sinh ra cũng là file YAML trong repo, nên ai cũng đọc và sửa được ngoài QA Desk. Một kịch bản chạy như một suite: Maestro là một lệnh nữa trong allowlist, xuất JUnit và ảnh chụp, và QA Desk đã biết lưu, so sánh, báo cáo những thứ đó.

Hai điểm phải kiểm trước (spike DA-001):
- Maestro native trên Windows có ổn với máy ảo của máy này không.
- Biến tiền tố `MAESTRO_` có dùng được trực tiếp trong `inputText`, để mật khẩu không bao giờ nằm trên dòng lệnh không.

Nếu spike thất bại, đường lui là chạy Maestro trong WSL2. Phương án cuối là một bộ chạy tối giản dựa trên `adb` + `uiautomator`.

## 4. Mô hình dữ liệu

### 4.1 App cần test: trong repo, `.fiza-qa/project.yaml`

Cấu hình đi theo code của app: ai có repo là có cấu hình, và nó được review như code.

```yaml
apps:
  - id: fizahub-android
    name: FizaHUB (Android)
    platform: android            # android | web
    environments:
      staging:
        appId: vn.fizahub.app.stg      # mỗi môi trường một package: không thể nhầm bản
        build: build/app/outputs/bundle/stagingRelease/app-staging-release.aab
      production:
        appId: vn.fizahub.app
        build: build/app/outputs/bundle/productionRelease/app-production-release.aab
    login: flows/login.yaml      # flow con, nhận ${MAESTRO_QA_USERNAME} ${MAESTRO_QA_PASSWORD}
    cleanup: flows/cleanup.yaml  # tuỳ chọn: dọn dữ liệu kịch bản ghi đã tạo trên staging
    productionGuard:             # nhãn không bao giờ được bấm khi chạy production
      - Thanh toán
      - Tạo đơn
      - Xoá
      - Huỷ đơn
```

App web dùng `platform: web` và mỗi môi trường khai `url` thay cho `appId` và `build`.

**Phân biệt môi trường:**
- Cách mạnh nhất là **mỗi môi trường một `appId`** (Android `applicationIdSuffix`). Trước khi chạy, QA Desk kiểm tra đúng package đó đã được cài, hoặc tự cài từ `build`.
- App chỉ có một package thì khai thêm `check`: một dòng chữ chỉ có ở staging, hoặc `versionName` chứa hậu tố. QA Desk kiểm tra điều kiện đó trước bước đầu tiên.

### 4.2 Tài khoản demo: kho của team, Firestore

`teams/{teamId}/qaAccounts/{accountId}`:

| Trường | Ghi chú |
|---|---|
| `app`, `environment` | Ví dụ `fizahub-android`, `staging` |
| `role` | Nhãn vai trò do team đặt: "Chủ shop", "Nhân viên"… Kịch bản chọn tài khoản theo vai trò, không theo người |
| `username` | **Mã hoá** |
| `password`, `extra{…}`, `totpSecret` | **Mã hoá**. `extra` cho mã cửa hàng, PIN…; mỗi trường thành `${MAESTRO_QA_<TÊN>}` |
| `access` | `readWrite` hoặc `readOnly`. Tài khoản production luôn `readOnly` |
| `status` | `ok`, `loginFailed` (kèm thời điểm, thông báo), `disabled` |
| `notes`, `createdBy`, `updatedAt` | |

Các collection còn lại:
- `qaAccountLeases/{accountId}`: `holderUid`, `machine`, `runId`, `expiresAt`. Mượn bằng transaction, gia hạn mỗi phút khi đang chạy, trả khi xong. Lease quá hạn (máy tắt giữa chừng) thì người khác lấy được.
- `qaAccountAudit/{autoId}`: chỉ thêm, không sửa. Ghi ai tạo/sửa/xoá, ai xem mật khẩu, ai mượn tài khoản cho lượt nào.

**Mã hoá đầu-cuối:**
1. Admin tạo kho bằng một passphrase.
2. Firestore lưu `salt`, tham số KDF và một *key check* (bản mã của một chuỗi cố định, để biết passphrase nhập đúng).
3. Khoá AES-GCM 256 sinh từ passphrase bằng Argon2id của gói `cryptography`, gói AMC đang dùng.
4. Mỗi thành viên nhập passphrase một lần; khoá được giữ trong Windows secure storage của máy đó.
5. Đổi passphrase thì mã hoá lại toàn bộ kho.

Firebase, kể cả ai có quyền vào console, chỉ thấy bản mã.

**Phân quyền:**
- Firestore rules: thành viên đọc được `qaAccounts`; chỉ `admin` được ghi; ai cũng chỉ tạo hoặc gia hạn lease của chính mình, hoặc lease đã hết hạn; audit chỉ được thêm.
- Trên giao diện, mật khẩu luôn bị che; chỉ Admin có nút xem/copy, và mỗi lần xem đều được ghi audit.
- **Giới hạn cần nói rõ:** ai chạy được automation thì về kỹ thuật cũng lấy được mật khẩu (máy đó phải giải mã để nhập vào app). Vì vậy demo account phải là tài khoản test riêng, quyền tối thiểu, không bao giờ là tài khoản cá nhân.

**AMC không có Firebase:** kho chuyển về chế độ trên máy này (secure storage), giống workspace local của API Tool.

### 4.3 Kịch bản tự thao tác: trong repo

`TestScenario` có thêm `kind: manual | automation`. Kịch bản automation có thêm:
- `app`: id app ở 4.1;
- `role`: vai trò tài khoản cần dùng;
- `writes`: `true` hoặc `false`;
- `environments`: môi trường được phép chạy;
- `flow`: đường dẫn tới `.fiza-qa/flows/<id>.yaml`, file do QA Desk sinh từ các bước.

`scenarios.json` lên `schemaVersion: 2`, và vẫn đọc được bản 1.

Các bước dựng sẵn (không cần code), mỗi bước sinh ra một hoặc vài lệnh Maestro:

| Bước | Maestro |
|---|---|
| Mở app (tuỳ chọn xoá dữ liệu) | `launchApp` với `clearState` |
| Đăng nhập bằng tài khoản demo | `runFlow: login.yaml` |
| Bấm vào *chữ / id* | `tapOn` |
| Nhập *giá trị hoặc biến* | `inputText` |
| Thấy / không thấy *chữ* | `assertVisible` / `assertNotVisible` |
| Chờ tới khi thấy *chữ* | `extendedWaitUntil` |
| Cuộn tới *chữ* | `scrollUntilVisible` |
| Quay lại | `back` |
| Chụp màn hình *tên* | `takeScreenshot` |
| Chạy flow con | `runFlow` |

Bước nào không có sẵn thì chuyển sang sửa YAML trực tiếp; QA Desk vẫn đọc được kịch bản đó.

Biến có sẵn trong kịch bản:
- `${MAESTRO_QA_USERNAME}`, `${MAESTRO_QA_PASSWORD}`, `${MAESTRO_QA_OTP}` (Phase E), `${MAESTRO_QA_<EXTRA>}`;
- `${MAESTRO_QA_RUN_ID}`: mã ngắn của lượt chạy, dùng đặt tên cho dữ liệu kịch bản tạo ra, ví dụ khách hàng "QA-7f3c". Nhờ vậy dữ liệu dễ nhận ra và dễ dọn.

## 5. Một lượt chạy kịch bản tự thao tác

1. **Kiểm tra trước khi chạy (preflight):**
   - Maestro và Java ≥ 17 đã có;
   - kho đã mở khoá;
   - có tài khoản đúng app, môi trường và vai trò, trạng thái không phải `disabled`;
   - đã chọn thiết bị (với Android);
   - kịch bản ghi không được chạy trên production;
   - với production: soát tĩnh flow, gặp nhãn nằm trong `productionGuard` thì chặn.

   Lỗi nào cũng hiện ở thanh dưới cùng, kèm nút sửa, như các kiểm tra hiện có.
2. **Production:** banner đỏ PRODUCTION trên thanh hành động, và một hộp xác nhận nêu rõ app, tài khoản (vai trò) và các kịch bản chỉ đọc sắp chạy.
3. **Mượn tài khoản:** transaction lease. Tài khoản đang có người dùng thì lượt chạy chờ và hiện "đang được … dùng, còn ~N phút"; hết thời gian chờ thì chọn tài khoản khác cùng vai trò nếu có.
4. **Khoá thiết bị:** dùng `DeviceRunLock`, xếp hàng chung với Kiểm tra AAB và các suite mobile.
5. **Chuẩn bị app:** kiểm tra đúng `appId` và `versionCode` của bản `build`. Thiếu hoặc cũ hơn thì cài lại bằng bước cài của Kiểm tra AAB.
6. **Chạy:**

   ```
   maestro test <flow> --format junit --output <artifact>/report.xml --debug-output <artifact>/debug
   ```

   Chạy qua `SafeProcessRunner`. Tài khoản chỉ đi qua **biến môi trường tiến trình** `MAESTRO_QA_*`, không bao giờ nằm trên dòng lệnh.
7. **Che giá trị:** mọi giá trị đã giải mã (mật khẩu, OTP, các trường `extra`) được thay bằng `••••` trong log trực tiếp, log lưu, JUnit, lịch sử và báo cáo issue. Áp dụng cho cả secret theo phiên hiện có. Ô mật khẩu trên màn hình đã bị app che sẵn; số điện thoại vẫn có thể hiện trong ảnh chụp, và điều này được ghi rõ trong hướng dẫn.
8. **Đọc kết quả:** JUnit cho từng bước qua hay lỗi. Bước lỗi kèm ảnh chụp lấy từ `debug/`. Lưu vào lịch sử (bảng mới `flow_steps`) và hiện ở Kết quả thành dòng thời gian các bước.
9. **Kết thúc:** trả lease.
   - Flow đăng nhập thất bại thì đánh dấu tài khoản `loginFailed` và dừng các kịch bản còn lại của tài khoản đó (khỏi lỗi dây chuyền), báo "Tài khoản *Chủ shop · staging* không đăng nhập được".
   - Kịch bản ghi trên staging chạy xong thì chạy `cleanup` nếu app có khai.

## 6. Giao diện

- **Kịch bản:**
  - Cột trái có thêm mục **Ứng dụng** (các app khai trong `project.yaml`) và **Tài khoản demo**, gom theo app, môi trường và vai trò, với trạng thái, ai đang mượn và lần dùng cuối.
  - Nút **Kho tài khoản** mở bảng bên: Admin thêm/sửa tài khoản, nút **Thử đăng nhập** chỉ chạy flow đăng nhập để kiểm tra tài khoản.
  - Form test case có công tắc **Tự thao tác**. Bật lên thì phần "Các bước" thành danh sách bước có cấu trúc (thêm, kéo sắp xếp, xoá), cùng ô chọn app, vai trò, đọc/ghi và môi trường cho phép.
- **Chạy test:**
  - Kịch bản tự thao tác hiện trong cây dưới nhóm *Kịch bản tự động* của mỗi nguồn, nên chạy chung được với suite.
  - Thanh chip có thêm **Tài khoản: Chủ shop · staging** (bấm để đổi tài khoản hoặc môi trường) và **Môi trường: staging / production**.
  - Log hiện tiến độ theo từng bước.
- **Kết quả:** kịch bản tự thao tác có dòng thời gian từng bước kèm ảnh. Báo cáo issue ghi bước lỗi, ảnh chụp, app, môi trường và vai trò tài khoản, không bao giờ ghi thông tin đăng nhập.
- **Lần đầu dùng:** thẻ hướng dẫn 4 bước:
  1. Tải Maestro (một nút, có kiểm SHA-256).
  2. Mở khoá hoặc tạo kho tài khoản.
  3. Khai app trong `project.yaml` (có mẫu sẵn).
  4. Tạo kịch bản đầu tiên: *Đăng nhập và thấy trang chủ*.

## 7. Lộ trình

### Phase A: nền và spike (2–3 ngày)

- **DA-001 Spike:**
  - Maestro native Windows trên máy ảo của máy này;
  - `MAESTRO_*` dùng được trong `inputText`;
  - `--format junit` và `--debug-output` cho ra đúng thứ cần đọc;
  - chọn được ô nhập trên màn đăng nhập FizaHUB bằng hint text.

  Thất bại thì quyết định đường lui (WSL2 hoặc adb) trước khi làm tiếp.
- **DA-002** `MaestroManager`: ghim phiên bản, tải, kiểm SHA-256, cài vào `qa_desk/tools/maestro`, kiểm Java ≥ 17. Thêm `maestro` vào allowlist, chỉ chấp nhận đường dẫn do QA Desk quản lý.
- **DA-003** Che giá trị secret trong runner, cho cả secret theo phiên hiện có.
- **DA-004** Đọc `apps:` trong `project.yaml`, cập nhật `tool/qa_validate_sources.dart`; scenario `schemaVersion: 2`, sinh YAML từ các bước; chạy một flow như một suite, đọc JUnit và ảnh.
- **DA-005** Kho tài khoản trên máy (secure storage), để Phase A dùng được ngay.

### Phase B: kho của team (2–3 ngày)

- **DA-006** Collection Firestore và rules; test rules bằng Firestore emulator (repo đã có `firebase.json`).
- **DA-007** Mã hoá đầu-cuối: tạo kho, mở khoá, đổi passphrase, key check.
- **DA-008** Lease (mượn, gia hạn, trả, thu hồi khi hết hạn) và audit.
- **DA-009** Chuyển kho trên máy lên team, có xác nhận; giữ chế độ trên máy khi không có Firebase.

### Phase C: soạn và chạy trong giao diện (3–4 ngày)

- **DA-010** Bảng Kho tài khoản, Thử đăng nhập, trạng thái và người đang mượn.
- **DA-011** Trình soạn bước trong form test case.
- **DA-012** Kịch bản tự động trong cây Chạy test; chip Tài khoản và Môi trường; preflight mới.
- **DA-013** Lớp chặn production: banner, hộp xác nhận, soát `productionGuard`, chặn kịch bản ghi.
- **DA-014** Dòng thời gian từng bước ở Kết quả; báo cáo issue có bước lỗi và ảnh.

### Phase D: FizaHUB làm mẫu (1–2 ngày, cần bạn cấp tài khoản và bản build)

- **DA-015** Khai `apps:` cho `fizahub_app`. Viết `login.yaml` theo hint text, đề xuất PR thêm `Semantics(identifier: …)` cho màn đăng nhập.
- **DA-016** Ba kịch bản mẫu: *Đăng nhập và thấy trang chủ* (đọc), *Xem danh sách đơn* (đọc), *Tạo đơn nháp* (ghi, chỉ staging), cùng `cleanup.yaml`.
- **DA-017** Chạy thật trên máy ảo bằng demo account staging, sau đó một lượt chỉ đọc trên production.

### Phase E: mở rộng (tuỳ chọn)

App web (Maestro web, hoặc Playwright nếu Maestro web chưa đủ), OTP dạng TOTP, chọn phần tử bằng cách bấm trên ảnh màn hình đang chạy, chạy theo lịch, gửi tóm tắt qua Telegram.

## 8. Rủi ro

| Rủi ro | Cách xử lý |
|---|---|
| Maestro native Windows chưa đủ ổn | Spike DA-001 đặt đầu tiên; đường lui WSL2, rồi đến adb |
| App Flutter: Key vô hình với Maestro, chọn theo chữ thì vỡ khi đổi câu chữ | Bắt đầu bằng hint/text; đề xuất app thêm `Semantics(identifier:)` cho phần tử kịch bản dùng |
| UI automation không thể đảm bảo tuyệt đối không ghi trên production | Ba lớp ở phía QA Desk (khai báo, soát nhãn, xác nhận). Lớp quan trọng nhất phải ở backend: **tài khoản production không có quyền ghi** |
| Hai người dùng chung tài khoản, app chỉ cho một phiên | Lease theo tài khoản; nên có vài tài khoản cùng vai trò |
| Dữ liệu staging bị rác dần | `${MAESTRO_QA_RUN_ID}` trong tên dữ liệu và flow `cleanup` |
| Lộ mật khẩu qua log, ảnh, dòng lệnh | Chỉ đi qua biến môi trường; che trong mọi đầu ra; audit mỗi lần xem |
| Quên passphrase của kho | Admin tạo lại kho và nhập lại tài khoản; hướng dẫn lưu passphrase trong password manager của team |
| Tài khoản có OTP SMS hoặc captcha | Không hỗ trợ; TOTP để Phase E |

## 9. Cần chốt trước khi làm

1. **Maestro làm công cụ**, với spike DA-001 làm điều kiện. Đề xuất: đồng ý.
2. **Cấu hình app và kịch bản nằm trong repo dự án, tài khoản nằm trong kho team.** Đề xuất: đồng ý.
3. **Kho mã hoá bằng passphrase của team** (Firebase chỉ thấy bản mã), thay vì chỉ dựa vào Firestore rules. Đề xuất: passphrase.
4. **Tài khoản production phải là tài khoản không có quyền ghi ở phía backend.** Việc này team backend làm, QA Desk không thay được.
5. **Cho Phase D, bạn cần cấp:** một demo account staging (và một production chỉ đọc nếu muốn), bản AAB/APK staging và production, và cho biết staging/production có tách `applicationId` không.

## 10. Tiến độ

Cập nhật 2026-10-02, nhánh `feature/qa-desk-module`, chưa commit.

| Mục | Trạng thái | Ghi chú |
|---|---|---|
| DA-001 Spike | Xong | Maestro 2.11.0 native Windows trên máy ảo ZFold_3: `MAESTRO_*` dùng được trong `appId:` và `inputText`; `--test-output-dir` cho `commands.json`, ảnh bước lỗi và ảnh `takeScreenshot`. Không cần đường lui WSL2/adb. |
| DA-002 `MaestroManager` | Xong | Cài vào `qa_desk_tools/maestro/2.11.0` (cạnh `qa_desk/`, để không chặn bước nhập dữ liệu app cũ). Chạy thẳng bằng `java -classpath lib\* maestro.cli.AppKt`: Dart không đặt ngoặc cho đường dẫn `.bat` có dấu cách. |
| DA-003 Che secret | Xong | Tài khoản demo và secret theo phiên bị che `••••` trong log, JUnit, `commands.json`, `maestro.log`. |
| DA-004 `apps:`, schema 2, sinh flow | Xong | Manifest chỉ có `apps:` (không suite) cũng hợp lệ. `tool/qa_validate_sources.dart` và `tool/qa_validate_catalogs.dart` hiểu app và kịch bản tự thao tác. |
| DA-005 Kho trên máy | Xong | Secure storage (DPAPI). |
| DA-006 Firestore rules | Xong, **chưa deploy** | 5/5 test trên emulator (`test/firestore/run_rules_test.ps1`). |
| DA-007 Mã hoá đầu-cuối | Xong một phần | Tạo kho, mở khoá, khoá lại, key check. **Chưa có đổi passphrase**: hiện phải tạo lại kho. |
| DA-008 Lease và audit | Xong | Lease 10 phút, gia hạn mỗi phút, chờ tối đa 5 phút; audit tạo/sửa/xoá/xem/mượn. |
| DA-009 Chuyển kho lên team | Xong | Nút *Chép từ kho trên máy này* (Admin). |
| DA-010 → DA-014 Giao diện | Xong | Kho tài khoản + thẻ Maestro, trình soạn bước, nhóm *QA Desk tự thao tác* trong cây, chip *Môi trường app* và *Tài khoản demo*, hộp xác nhận production, *Các bước* ở Kết quả. Báo cáo issue lấy dòng `Bước lỗi:` từ log. |
| DA-015 FizaHUB `apps:` + `login.yaml` | Xong | Selector màn đăng nhập đã thử trên máy ảo (chỉ kiểm tra hiển thị, không nhập). `build:` để trống: điền đường dẫn APK staging/production. Đề xuất PR `Semantics(identifier:)` chưa làm. |
| DA-016 Kịch bản mẫu | Xong một phần | *Đăng nhập và thấy trang chủ*, *Xem danh sách đơn hàng* (chỉ đọc). **Chưa có** *Tạo đơn nháp* và `cleanup.yaml`: cần biết cách dọn đơn trên staging. |
| DA-017 Chạy thật | **Chờ bạn** | Cần demo account staging trong kho. |

Lỗi tìm ra khi viết test và đã sửa: mở khoá kho của team luôn báo "Kho đang khoá"; lỗi đăng nhập không được nhận ra vì Maestro chỉ ghi các lệnh đã chạy tới (giờ dựa vào bước chạy flow đăng nhập bị lỗi); flow production chưa có trên đĩa thì bỏ qua soát `productionGuard` (giờ soát lại sau khi sinh flow).

Test: `qa_desk_flow_compiler_test`, `qa_desk_account_vault_test`, `qa_desk_automation_runner_test`, `qa_desk_automation_view_test`, thêm vào `qa_desk_source_discovery_service_test`. Toàn bộ: 778 qua, 1 lỗi có từ trước (`machine_power_service_test`).
