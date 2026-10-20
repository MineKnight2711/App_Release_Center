# AMC — Kế hoạch Feature Analytics

Ngày: 20/10/2026. Trạng thái: đã triển khai lát cắt pilot `bundle.check` trong code; xem [phạm vi, giới hạn và cách chạy pilot](feature-analytics-pilot.md). Các phần còn lại bên dưới là kế hoạch tổng thể, chưa phải toàn bộ đã hoàn thành.

## 1. Mục tiêu và phạm vi đề xuất

Thêm màn hình **Thống kê sử dụng** để chủ sản phẩm trả lời:

1. Tính năng nào được nhiều người sử dụng, với tần suất bao nhiêu?
2. Tính năng nào được mở nhưng không được dùng, hoặc dùng hay thất bại?
3. Tính năng nào có người quay lại sử dụng qua nhiều ngày?
4. Nên đầu tư, cải tiến cách tiếp cận, gộp hay cân nhắc ngừng tính năng nào?

Phạm vi đã được xác nhận: **toàn bộ người dùng/team, có dashboard quản trị**. Client có hàng đợi local để hoạt động khi mất mạng, sau đó đồng bộ về backend trung tâm. Dashboard toàn AMC dành cho chủ sản phẩm; team admin chỉ xem team được cấp quyền. Hoạt động chưa đăng nhập không được gán ngược cho tài khoản đăng nhập sau đó.

MVP đo hoạt động có ý nghĩa của người dùng. Hoạt động tự động, lịch chạy, Telegram và remote có nguồn riêng để không làm phồng mức sử dụng trực tiếp. Chưa làm session replay, heatmap, A/B testing hay hệ thống tự động xóa tính năng.

## 2. Hiện trạng trong repository

| Thành phần | Hiện trạng và cách tận dụng |
|---|---|
| Flutter/GetX, `lib/app/bindings/app_binding.dart` | Đăng ký dịch vụ analytics dùng chung, inject vào controller/service |
| `lib/app/controllers/app_shell_controller.dart` | Có tab state và `markCommandUsed`; danh sách gần đây chưa phải lịch sử analytics |
| `lib/app/views/home_widgets/command_palette.dart` | Có command ID; một số ID gắn dự án/lane, phải map sang feature ID cố định |
| Các module Plan Studio, QA Desk, Bundle Check, Safe, Mail Cleaner | Đo mở module tại điểm điều hướng, đo kết quả tại nơi hoàn thành nghiệp vụ |
| `lib/app/modules/qa_desk/services/report_analytics_service.dart` | Thống kê kết quả test, chưa phải mức sử dụng AMC |
| `lib/app/data/amc_api_client.dart` và `cloudflare/amc-api/src/index.ts` | Có client HTTP, authenticated routes, có thể thêm endpoint nhận batch |
| `cloudflare/amc-api/wrangler.jsonc` | Có D1, đang dùng chung database với relay; cần kiểm soát tải analytics |
| `lib/app/models/auth_models.dart`, `cloudflare/amc-api/src/teams.ts` | Hiện có team admin/dev; chưa có quyền xem analytics toàn sản phẩm |
| `pubspec.yaml` và `app_build_stamp.dart` | Cần build ID ổn định do pipeline cấp; timestamp file chỉ hỗ trợ chẩn đoán |

Không đưa toàn bộ console log/build log lên analytics. Log chẩn đoán, audit bảo mật và thống kê sử dụng có mục tiêu, thời gian lưu và quyền đọc riêng.

## 3. Định nghĩa “sử dụng” và các chỉ số

Mỗi tính năng có `feature_id` cố định, độc lập với tên hiển thị. Registry khai báo module cha, nền tảng/phiên bản hỗ trợ, quyền cần thiết, thao tác được tính là sử dụng, cách xác định thành công và trạng thái triển khai tracking.

| Chỉ số | Định nghĩa trong khoảng thời gian và bộ lọc đang chọn |
|---|---|
| Người dùng hoạt động đủ điều kiện | Tài khoản có tương tác chủ động với AMC, bật đo lường, chạy bản có tracking và được phép truy cập tính năng |
| Người dùng tính năng | Số tài khoản riêng biệt bắt đầu ít nhất một thao tác có ý nghĩa; không tính chỉ mở màn hình |
| Tỷ lệ sử dụng | Người dùng tính năng / người dùng hoạt động đủ điều kiện; hiển thị cả tử số và mẫu số |
| Lượt dùng | Số operation khác nhau được bắt đầu; retry gửi dữ liệu không phải lượt dùng mới |
| Lượt thành công | Operation đạt kết quả nghiệp vụ được registry định nghĩa |
| Tỷ lệ thành công | Thành công / (thành công + thất bại); báo riêng hủy, đang chạy và thiếu kết quả |
| Quay lại dùng | Người dùng thao tác trong ít nhất 2 ngày khác nhau / người dùng tính năng trong kỳ |
| Xu hướng | So với kỳ trước cùng độ dài, kèm số mẫu và thay đổi phạm vi phiên bản/nền tảng |
| Thời lượng thao tác | p50/p95 của operation đã hoàn thành, không phải thời gian để màn hình mở |

Tỷ lệ quay lại trên đây là repeated usage, không gọi là retention D7. Retention theo cohort có thể bổ sung sau. Với tài khoản mới cuối kỳ, dashboard ghi rõ số ngày có thể quan sát.

Một lần thao tác tạo nhiều đối tượng vẫn là một operation: tạo 100 task hàng loạt = 1 lượt bulk-create, có `item_count_bucket` đi kèm. Autosave, rebuild widget, polling API, heartbeat remote và reminder tự chạy không được tính thành lượt dùng chủ động.

Ngày thống kê MVP dùng UTC để thống nhất tổng hợp; dashboard ghi rõ múi giờ. Không lấy app còn chạy trong tray làm người dùng hoạt động. Client ghi `app.active_day` ở lần tương tác chủ động đầu ngày và `feature.eligible_day` cho từng feature người dùng có quyền truy cập; cập nhật khi quyền hoặc khả năng truy cập thay đổi. Thiếu công cụ/cấu hình là lý do chặn thao tác, không âm thầm loại người đó khỏi mẫu số.

**Tránh đọc sai dữ liệu:**

- Registry hiển thị cả tính năng có 0 sự kiện. Phân biệt `chưa gắn tracking`, `chưa đủ dữ liệu`, `không áp dụng` và `đã đo, chưa ghi nhận sử dụng`.
- Người tắt analytics và client cũ nằm ngoài mẫu được quan sát. Chỉ hiển thị độ phủ toàn bộ cài đặt khi có nguồn inventory đáng tin cậy; nếu chưa có phải ghi “chưa biết”.
- Không cộng unique users của các ngày, các nền tảng hoặc các tính năng con. Tính distinct trên toàn khoảng thời gian và scope được chọn.
- Một user dùng desktop và mobile vẫn là một user ở tổng hợp tài khoản. Thiết bị local không đăng nhập chỉ có chỉ số thiết bị local.
- Pipeline còn thiếu hoặc dữ liệu đồng bộ chậm thì chưa kết luận “không ai dùng”. Hiển thị thời điểm cập nhật và các chỉ số chất lượng dữ liệu.

## 4. Danh mục ưu tiên gắn tracking

Đo `feature.opened` ở các module chính ngay từ đầu. Sau đó ưu tiên thao tác theo bảng; các hàng chưa gắn đủ phải có nhãn coverage.

| Nhóm / feature ID mẫu | Thao tác có ý nghĩa | Hoàn thành thành công khi |
|---|---|---|
| Release: `release.android`, `release.ios` | Chạy workflow phát hành | Workflow đạt trạng thái thành công đã định nghĩa |
| Store: `store.version_check` | Chủ động kiểm tra phiên bản | Có kết quả kiểm tra hợp lệ |
| Plan Studio: `plan.create`, `plan.bulk_create`, `plan.ai_generate`, `plan.reminder` | Tạo plan/task, tạo hàng loạt, tạo bằng AI, lưu nhắc hẹn | Ghi dữ liệu hoặc tạo kết quả thành công |
| QA Desk: `qa.run`, `qa.report_export` | Chạy test, xuất báo cáo | Có kết quả run hợp lệ hoặc xuất được file |
| Bundle Check: `bundle.check`, `bundle.device_run` | Kiểm tra AAB, chạy thử | Có báo cáo kiểm tra/chạy thử hợp lệ |
| API Tools: `api.send`, `api.collection_import` | Gửi request, nhập collection | Nhận phản hồi hoặc lưu collection thành công |
| Safe: `safe.item_save`, `safe.secret_scan` | Lưu mục, quét secret | Lưu thành công hoặc có báo cáo quét |
| Mail Cleaner: `mail.scan`, `mail.cleanup` | Quét thư, thực hiện dọn thư | Quét xong hoặc bước dọn đã được server xác nhận |
| Remote: `remote.release`, `remote.wake` | Gửi lệnh release, đánh thức máy | Remote release hoàn tất; wake có xác nhận host online |
| FlowFin: `flowfin.import`, `flowfin.reconcile` | Import, đối soát | Nghiệp vụ xác nhận thành công |
| Khám phá: `shell.command_palette` | Chọn lệnh thực thi | Lệnh được dispatch; kết quả nghiệp vụ đo tại feature đích |

QA chạy xong nhưng test fail và AAB kiểm tra xong nhưng phát hiện lỗi vẫn là **tính năng hoạt động thành công**. Lưu `result_category` riêng cho kết quả đánh giá. API nhận HTTP 4xx/5xx vẫn có thể là một lần gửi request thành công về mặt công cụ; tách HTTP status class khỏi lỗi transport. Remote gửi packet/lệnh thành công chưa đồng nghĩa tác vụ từ xa đã thành công.

MVP chi tiết: Release, Plan Studio, Bundle Check, QA Desk, API Tools. Các nhóm còn lại có số lượt mở trước, bổ sung thao tác ở đợt kế tiếp. Safe share chỉ thêm vào registry khi phần tính năng đó đã ổn định và được phát hành.

## 5. Hợp đồng sự kiện

Các tên sự kiện chuẩn: `app.active_day`, `feature.eligible_day`, `feature.opened`, `action.started`, `action.completed`, `action.failed`, `action.cancelled`, `action.blocked`.

`feature.opened` ghi khi điều hướng chủ động vào một màn hình, không ghi ở `build()`. `action.started` ghi khi nghiệp vụ chấp nhận bắt đầu; validation hoặc thiếu cấu hình ghi `action.blocked`. Operation chỉ có tối đa một kết quả cuối. Dùng enum/schema allowlist thay vì nhận `Map` tùy ý.

```json
{
  "schema_version": 1,
  "event_id": "uuid",
  "occurred_at": "2026-10-20T08:00:00Z",
  "session_id": "random-session-id",
  "operation_id": "random-operation-id",
  "feature_id": "bundle.check",
  "event_name": "action.completed",
  "platform": "windows",
  "app_version": "0.1.0+1",
  "build_id": "pipeline-build-id",
  "environment": "production",
  "source": "toolbar",
  "initiator": "human",
  "duration_ms": 1800,
  "properties": { "result_category": "issues_found" }
}
```

`operation_id` bắt buộc với action, không áp dụng cho mở trang/ngày hoạt động. Thêm `visit_id` cho lần mở màn hình và các action bắt đầu từ màn hình đó để ghép funnel; đường chạy trực tiếp không có visit được thống kê riêng. `source` là enum như toolbar, menu, palette, shortcut, mobile_remote, telegram, schedule. `initiator` phân biệt human/automation. Không gửi nguyên command ID có tên lane/dự án; map sang ID trong registry.

Server bổ sung `received_at`, danh tính phân tích và scope từ phiên đăng nhập; không tin user ID/role client tự khai. Team context được chụp lúc event phát sinh, server kiểm tra quyền khi nhận. Event thuộc tài khoản A không bao giờ gửi bằng session B. Đổi team không gán lịch sử cũ sang team mới; không còn quyền thì loại event đó với lý do rõ ràng.

Đối với tác vụ mobile → desktop, truyền correlation ID qua lệnh remote. Chỉ một bên được chỉ định phát kết quả cho operation logic; các bước truyền lệnh có event riêng, không cộng thành nhiều lượt release. Tác vụ hệ thống/Telegram chưa gắn được người khởi tạo vẫn có operation count riêng và không tính vào unique users chủ động.

Không thu thập email, tên dự án, đường dẫn máy, URL/request body, token, mật khẩu, nội dung Safe, nội dung thư, dữ liệu giao dịch, prompt AI hoặc nội dung task. Lỗi analytics chỉ có mã đã chuẩn hóa, không chứa exception/stack/raw response. Dùng định danh phân tích do server sinh, hạn chế quyền với bảng ánh xạ danh tính.

## 6. Kiến trúc đề xuất

```text
Điểm điều hướng / controller / service
               ↓
FeatureAnalyticsService + FeatureRegistry
               ↓
SQLite outbox riêng → gửi batch nền → AMC API Worker → D1 analytics tables
                                                         ↓
                                               API truy vấn / tổng hợp
                                                         ↓
                                         Màn hình Thống kê sử dụng trong AMC
```

### Client

- SQLite riêng trong application-support, không dùng database Plan Studio làm nơi chứa analytics toàn app. API ghi nhận bất đồng bộ, không chặn kết quả nghiệp vụ.
- Giới hạn khởi điểm: 10.000 event hoặc 10 MB, TTL hàng đợi 7 ngày; khi đầy loại event cũ và tăng bộ đếm dropped. Tất cả là cấu hình có thể điều chỉnh sau pilot.
- Gửi khi có mạng, khoảng 60 giây hoặc đủ 50 event; mỗi request tối đa 100 event/128 KB. Flush khi background là best-effort, không phụ thuộc app thoát sạch.
- Retry có exponential backoff và jitter, tuân thủ `Retry-After`. Backend lỗi không hiện popup lỗi tính năng và không làm logout người dùng chỉ vì đường gửi analytics lỗi.
- ACK theo `event_id`: accepted/duplicate/permanently_rejected. Chỉ xóa event đã ACK; lỗi mạng/5xx giữ lại. 401 tạm dừng chờ cùng tài khoản xác thực lại, 403 xử lý theo scope; lỗi schema không retry vô hạn.
- Khi đăng xuất, hủy request đang chờ và xóa outbox của tài khoản đó. Khi tắt thu thập, ngừng ghi/gửi và xóa queue chưa gửi. Không upload ngược lịch sử cá nhân chưa đăng nhập.
- Release có setting “Chia sẻ thống kê sử dụng”, thông báo ngắn về dữ liệu gửi; mặc định đề xuất chưa gửi trước khi người dùng bật. Debug/test dùng sink riêng, không trộn vào production. Chính sách rollout cần được chốt trước khi bật production.

### Backend và lưu trữ

- Đề xuất dùng Worker + D1 đã có cho pilot, tránh phải tích hợp thêm nền tảng analytics ngay. Đây là phương án kiến trúc, chưa phải kết luận về năng lực tải hoặc chi phí.
- `POST /v1/analytics/events`: auth, kiểm tra schema/allowlist, giới hạn batch/rate và chống ghi trùng. Ràng buộc event ID với principal; operation result có unique constraint riêng để tránh hai kết quả cuối.
- `GET /v1/analytics/features` và `/v1/analytics/features/:id`: bộ lọc khoảng ngày, platform, build, source, team theo quyền; trả cả coverage/quality metadata. API trả bảng đầy đủ từ registry, kể cả feature 0 lượt.
- Bảng đề xuất: `analytics_events`, `analytics_operations`, `analytics_feature_registry`, `analytics_daily_counts`, `analytics_subject_feature_day`, cùng mapping/quyền quản trị tối thiểu.
- Giữ raw events và dữ liệu distinct cấp subject/ngày 90 ngày; daily totals không định danh giữ 12 tháng. Dashboard unique users/repeated usage giới hạn 90 ngày. Với lịch sử dài hơn chỉ hiển thị số lượt/tổng hợp được hỗ trợ, không cộng daily unique để giả lập unique cả kỳ.
- Job tổng hợp có checkpoint và có thể chạy lại an toàn. Transaction chỉ cập nhật counters khi insert mới thành công; event đến muộn cập nhật lại ngày tương ứng. Cleanup chạy riêng, giới hạn batch để tránh ảnh hưởng DB dùng chung.
- Ghi UTC cả thời điểm phát sinh và thời điểm nhận. Chấp nhận offline tối đa 7 ngày theo TTL; thời gian tương lai lệch quá ngưỡng cấu hình được đánh dấu/quarantine, không âm thầm đổi sang ngày khác. Hiển thị độ trễ nhận dữ liệu và số bị loại.
- Event kết quả có thể đến trước started; ghép theo operation ID, kiểm tra cùng principal/feature. Operation thiếu terminal sau timeout riêng cho từng loại được xếp `unknown`, không tự coi là failure. Kết quả đến muộn sửa trạng thái và số liệu tương ứng.
- Theo dõi dung lượng, write/read volume, latency ingest/query trước khi mở rộng. Nếu analytics ảnh hưởng API chính hoặc tăng nhanh, tách D1 riêng trước, đánh giá kho phân tích chuyên dụng sau bằng số đo thực tế.

### Quyền truy cập

Team admin chỉ xem team của mình. Chủ sản phẩm được cấp quyền riêng `analytics_admin` phía server để xem tổng hợp toàn AMC; quyền này không suy ra từ `TeamRole.admin` hiện tại. Mọi lọc team đều kiểm tra server-side, kể cả export. Dashboard mặc định tổng hợp theo tính năng, không xếp hạng nhân viên.

MVP có nút tắt thu thập và quy trình quản trị xóa dữ liệu theo analytics subject; xóa raw, operation và subject-day, tính lại aggregate trong phần lịch sử còn tái dựng được. Dữ liệu đã tổng hợp không định danh ngoài retention không còn khả năng truy ngược theo tài khoản; cần mô tả rõ trong thiết lập thu thập.

## 7. Dashboard và cách đưa ra quyết định

Mục **Thống kê sử dụng** xuất hiện cho tài khoản có quyền, mở được từ command palette. Một màn hình chính gồm:

1. Bộ lọc 7/30/90 ngày, team, platform, build/version, nguồn human/automation; mặc định 30 ngày và human.
2. Tổng quan: người dùng quan sát được, số feature có tracking đầy đủ, lượt dùng, tỷ lệ hoàn thành và lần cập nhật gần nhất.
3. Bảng: tính năng, users, mẫu số đủ điều kiện, adoption, lượt dùng, thành công/thất bại/hủy/unknown, quay lại, xu hướng, coverage. Sắp xếp tăng/giảm để thấy cả dùng nhiều lẫn dùng ít.
4. Chi tiết tính năng: xu hướng theo ngày; funnel mở → bắt đầu → hoàn thành được ghép cùng visit/operation, tách các đường shortcut/automation không qua màn hình; các nhóm lỗi đã chuẩn hóa; p50/p95 khi đủ mẫu.
5. Xuất CSV theo bộ lọc và phạm vi quyền, không xuất nội dung nghiệp vụ hay định danh cá nhân.

| Mẫu dữ liệu | Hướng xử lý đề xuất |
|---|---|
| Nhiều người dùng, quay lại nhiều, ít lỗi | Tiếp tục đầu tư, bảo vệ độ ổn định |
| Nhiều người dùng, nhiều thất bại/hủy | Ưu tiên sửa lỗi và đơn giản hóa thao tác |
| Nhiều người mở, ít người bắt đầu | Xem khả năng tìm hiểu, điều kiện cấu hình, giá trị màn hình |
| Ít người dùng, nhóm dùng có quay lại đều | Có thể là tính năng chuyên biệt; xem giá trị với nhóm đó |
| Ít dùng kéo dài, ít quay lại, chi phí bảo trì cao | Đưa vào danh sách đánh giá gộp/ẩn/ngừng |
| Tracking thiếu, nhiều unknown hoặc mẫu quá ít | Sửa đo lường/thu thập thêm dữ liệu |

Ngưỡng ban đầu chỉ để gắn nhãn đánh giá: ít nhất 30 ngày có tracking ổn định; adoption dưới 5% qua 2 kỳ 30 ngày có thể vào danh sách xem xét. Nếu dưới 20 người đủ điều kiện thì ưu tiên số tuyệt đối và trao đổi trực tiếp, không kết luận từ phần trăm. Tính năng theo chu kỳ release có thể cần 90 ngày hoặc dài hơn.

Không tự động loại bỏ theo ngưỡng. Đọc thêm giá trị nghiệp vụ, phụ thuộc, nhu cầu theo vai trò và chi phí bảo trì. Luồng quyết định: kiểm tra chất lượng dữ liệu → tìm nguyên nhân → thử cải tiến cách tiếp cận/gộp → đo lại → thông báo kế hoạch ngừng và đường thay thế nếu vẫn phù hợp. Tính năng bảo mật, khôi phục và thao tác hiếm nhưng quan trọng cần đánh giá riêng.

## 8. Các đợt triển khai và tiêu chí nghiệm thu

| Đợt | Công việc | Điều kiện hoàn thành |
|---|---|---|
| 1 — Hợp đồng đo | Registry, event schema, định nghĩa success từng operation, privacy setting, quyền quản trị | Có bảng mapping feature → điểm phát event → metric; review cả 0/chưa đo |
| 2 — Nền tảng và lát cắt đầu tiên | Service, SQLite queue, ingest/idempotency, tracking `bundle.check`, truy vấn tối thiểu | Một lần kiểm tra AAB offline được đồng bộ chính xác một lần sau khi có mạng |
| 3 — Độ phủ MVP | Mở module, active/eligible days, action ở 5 nhóm ưu tiên, nguồn remote/automation | Nút, menu, palette và mobile không bỏ sót hoặc nhân đôi cùng thao tác |
| 4 — Dashboard | Bảng xếp hạng, chi tiết, bộ lọc, quyền, export, retention/rollup | Đối chiếu được với bộ dữ liệu biết trước, không có rò rỉ scope |
| 5 — Pilot | Bật trên nhóm nhỏ, kiểm tra dữ liệu và tải, sửa gaps | Dữ liệu đáng tin rồi mới mở rộng và bắt đầu kỳ đánh giá sản phẩm |
| 6 — Mở rộng | Safe, Mail Cleaner, FlowFin, nguồn tự động và tính năng con còn lại | Có coverage rõ ràng cho toàn bộ registry |

Ước lượng lập kế hoạch cho 1 dev quen codebase: khoảng 10–15 ngày làm việc cho đợt 1–4, tùy số thao tác thực sự gắn tracking và độ phức tạp remote. Pilot kỹ thuật thêm 3–7 ngày; quan sát hành vi 30–60 ngày sau đó. Đây là ước lượng ban đầu, cần cập nhật sau lát cắt đầu tiên; thời gian quan sát không phải thời gian lập trình.

### Kiểm tra bắt buộc khi triển khai

- Lặp gửi cùng batch, mất response sau khi server commit, restart giữa chừng: chỉ tính một lần.
- Widget rebuild/đổi tab/programmatic refresh/autosave không sinh lượt dùng giả; bulk 100 item vẫn 1 operation.
- Mất mạng, queue đầy, file queue lỗi, API timeout: thao tác nghiệp vụ vẫn hoàn thành; có dropped/invalid counters.
- Đổi tài khoản/team, logout, tắt tracking: không gửi nhầm danh tính hoặc lịch sử local chưa được phép.
- Batch trộn event hợp lệ/không hợp lệ, enum lạ, payload lớn, trường nhạy cảm: ACK/reject rõ và không lưu dữ liệu ngoài allowlist.
- Duplicate result, event đảo thứ tự, thiếu terminal, kết quả muộn, đồng hồ lệch, remote hai thiết bị: số liệu đúng hoặc được gắn trạng thái unknown rõ ràng.
- Cùng user hoạt động nhiều ngày/nền tảng: distinct theo kỳ đúng; daily rollup không cộng unique sai. 0 lượt và chưa tracking khác nhau.
- Team admin không xem team khác; team admin không tự có global analytics; export áp dụng cùng quyền.
- Debug/test không lọt production; retention/xóa dữ liệu chạy lại an toàn; đo thời gian ghi queue và tải backend trên dữ liệu pilot trước mở rộng.

## 9. Vị trí dự kiến thay đổi khi triển khai

- Thêm `lib/app/modules/analytics/`: models/registry, service, local outbox repository, uploader, controller và view dashboard.
- Đăng ký tại `lib/app/bindings/app_binding.dart`; tích hợp setting tại `lib/app/services/app_settings_service.dart` và `lib/app/views/app_settings_dialog.dart`.
- Instrument navigation tại shell/command palette và màn hình module; instrument operation ở controller/service sở hữu kết quả. Không thêm logging ở mọi widget/button một cách máy móc.
- Thêm `cloudflare/amc-api/src/analytics.ts`, routes, migration tiếp theo còn trống và test tương ứng; không cố định migration number khi đang có thay đổi khác trong workspace.
- Tách policy xử lý lỗi telemetry khỏi callback logout của client HTTP hiện tại; reuse transport/auth có kiểm soát.
- Thêm test cho event semantics, outbox, đồng bộ, auth scope và phép tính dashboard. Kế hoạch này chưa triển khai các thay đổi trên.

**Điểm khởi đầu đề xuất:** hoàn thành đường đo `bundle.check` từ thao tác đến dashboard, kiểm chứng offline/retry/duplicate, rồi nhân rộng cùng mẫu cho các tính năng khác.
