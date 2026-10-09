# Plan Studio — Nhắc hẹn và theo dõi tiến độ trên Windows

Ngày lập: 2026-09-21. Cập nhật triển khai: 2026-09-24.

## Đã triển khai theo yêu cầu bổ sung

- Plan/Task/Note đều có tab **Nhắc hẹn** riêng và nút dẫn vào từ Chi tiết.
- Ba chế độ: Ngày & giờ; Sau khoảng thời gian; Lặp định kỳ theo phút/giờ/ngày (ngày là 24 giờ).
- Chọn thời điểm bắt đầu lịch lặp; xem trước lần nhắc đầu tiên, preset 5/15/30/60 phút, validation và thông báo đã lưu.
- Lịch đã đặt có đếm ngược, giờ tiếp theo, chu kỳ, nút dừng. Board có badge thời gian nhắc; Hôm nay bổ sung nhắc sắp tới.
- Lặp theo khoảng thời gian cố định từ mốc bắt đầu. Đã xem/mở chi tiết/bắt đầu làm chuyển sang kỳ tương lai gần nhất; snooze giữ mốc chu kỳ. Một popup chờ xử lý, không tạo chồng popup qua mỗi kỳ. Done/archive/delete dừng lịch.
- SQLite schema 3 và backup JSON 3; đọc backup 1/2, migration giữ lịch cũ. Import lịch lặp vẫn tạm tắt để tránh nhắc ngoài ý muốn.
- Chưa có lịch theo thứ trong tuần/IANA timezone. Không tự cập nhật bản ứng dụng đã cài hoặc khởi động lại phiên người dùng.
- Kiểm chứng: 41 test Plan Studio qua; analyze module/test sạch; render kiểm tra giao diện 720px/420px. Test gồm recurrence, snooze, persistence, note, migration v1/v2 và backup. Hành vi sleep, nhiều màn hình và popup native trên bản này vẫn cần nghiệm thu máy thật.

Nội dung bên dưới là thiết kế gốc; mục này ghi nhận những thay đổi phạm vi sau đó.

## 1. Mục tiêu và phạm vi

Biến Plan Studio thành nơi theo dõi việc đang làm hằng ngày: đặt lịch cho Plan/Task, đến giờ hiện **cửa sổ popup lớn trên desktop Windows**, xem tiến độ và xử lý ngay mà không phải tìm lại board.

Hiểu yêu cầu “popup to ngay trên window” là cửa sổ độc lập nổi trên các cửa sổ ứng dụng thông thường, kể cả khi AMC đang thu nhỏ hoặc ẩn ở khay hệ thống. Các lựa chọn dưới đây là mặc định đề xuất để triển khai, không phải các yêu cầu người dùng đã chốt chi tiết.

**Bản đầu cần hoàn chỉnh:** deadline, nhắc một lần/nhắc trước hạn, popup tương tác, snooze, danh sách Hôm nay, lưu bền, chạy nền ở tray, khôi phục lịch sau restart/sleep. Dữ liệu tiếp tục local theo máy, không phụ thuộc AI, Firebase hay Internet.

**Sau bản đầu:** lịch lặp ngày/tuần, nhắc check-in định kỳ, bảng nhỏ ghim tiến độ, tổng kết tuần. Đồng bộ điện thoại/team, gửi Telegram, Windows service và tự đánh thức máy chưa thuộc phạm vi này.

## 2. Hiện trạng đã kiểm tra trong code

| Thành phần | Hiện tại | Việc cần bổ sung |
|---|---|---|
| `models/work_item.dart` | Plan/Task/Note, sáu trạng thái, priority, checklist, lịch sử, revision; chưa có deadline/reminder | Thêm thời gian kế hoạch tương thích dữ liệu cũ; model nhắc hẹn riêng |
| `repositories/local_plan_repository.dart` | SQLite schema 1; ticket lưu JSON; transaction, kiểm tra revision; backup JSON schema 1, import chỉ thêm ID mới | Migration, bảng lịch/occurrence, truy vấn đến hạn, backup schema mới |
| `views/plan_studio_view.dart` | Mở repository khi vào màn hình, đóng khi dispose | Chuyển quyền sở hữu repository sang runtime cấp ứng dụng |
| `controllers/plan_board_controller.dart` | Reload sau thao tác qua controller | Nhận sự kiện thay đổi từ popup và scheduler |
| `views/ticket_editor.dart` | Editor dạng panel trong app, autosave; có checklist và ghi chú | Khối Lịch hẹn; xử lý revision conflict với thao tác popup |
| `widgets/kanban_column.dart` | Tiến độ plan dựa trên số task con hoàn tất, bỏ task archived | Tái sử dụng cùng công thức ở popup/Hôm nay |
| `lib/main.dart`, `app_binding.dart` | Khởi tạo dịch vụ chung; có nhánh startup webview | Khởi tạo runtime Windows; nhánh riêng cho popup trước bootstrap dịch vụ chính |
| `windows/runner/` | Runner một cửa sổ chính, chưa có luồng tray/popup nhắc hẹn riêng | Window host, tray, sự kiện resume/unlock, đảm bảo một runtime lập lịch |

Nhắc hẹn không nên dùng timer thuộc widget hoặc chỉ dùng `showDialog`: vòng đời nhắc phải độc lập với route Plan Studio và popup phải tồn tại khi cửa sổ chính bị ẩn.

## 3. Trải nghiệm sử dụng

### 3.1. Đặt lịch trên ticket

Thêm khối **Lịch & nhắc hẹn** vào editor cho Plan/Task:

- Hạn hoàn thành: ngày + giờ, tùy chọn; chưa có hạn thì không gắn nhãn quá hạn.
- Nhắc vào thời điểm cụ thể, hoặc trước hạn: đúng giờ, 15 phút, 1 giờ, 1 ngày; tối đa ba mốc cho mỗi ticket ở bản đầu.
- Hiển thị giờ địa phương và thời điểm nhắc tiếp theo; có nút “Thử popup”. Popup thử không tạo occurrence thật và không sửa ticket.
- Cho phép nhắc khi chưa có deadline. Note chưa nhận lịch nhắc ở bản đầu.
- Hẹn giờ trong quá khứ cần lựa chọn rõ “Nhắc ngay” hoặc sửa giờ. Nhắc tương đối bắt buộc có deadline; bỏ deadline phải xử lý các lịch phụ thuộc trong cùng transaction.

Card trên board thêm badge hạn, quá hạn và biểu tượng nhắc. “Quá hạn” là nhãn tính từ thời gian, không thêm cột trạng thái mới.

### 3.2. Popup lớn: xem tình hình và làm ngay

Kích thước đề xuất **720 × 480 logical pixels**, co theo vùng làm việc màn hình; nội dung dài có scroll. Mặc định ở góc phải phía dưới, có thể kéo và nhớ vị trí theo màn hình; đổi màn hình phải đưa cửa sổ về vùng nhìn thấy.

Nội dung theo thứ tự:

1. Loại nhắc: “Đến giờ cập nhật tiến độ”, “Sắp đến hạn” hoặc “Đã quá hạn”; giờ hẹn và số phút trễ.
2. Dự án, mã ticket, tiêu đề, priority, trạng thái.
3. Tiến độ plan, ví dụ **6/10 task hoàn tất · 60%**, số task blocked và ba việc chưa xong gần nhất; task thì hiển thị checklist.
4. Lý do bị chặn hoặc ghi chú tiến độ mới nhất, nếu có.
5. Hành động: **Mở chi tiết**, **Bắt đầu làm**, **Hoàn tất**, **Nhắc lại 10/30/60 phút**, **Đã xem**. “Bị chặn” trong menu phụ yêu cầu nhập lý do.

Quy tắc tương tác:

- Popup xuất hiện ở lớp trên nhưng không tự lấy bàn phím khỏi ứng dụng đang gõ. Người dùng click mới tương tác; có thể tắt ghim trên cùng.
- Không tự biến mất trước khi người dùng xử lý; nút X/Escape có cùng nghĩa “Đã xem”, kết thúc lần nhắc hiện tại nhưng không hoàn tất ticket.
- Chỉ một cửa sổ nhắc, chứa hàng đợi và nhãn “1/4”; không mở hàng loạt cửa sổ. Nhiều mốc cùng ticket đã đến hạn được gom thành một card và ghi nhận từng occurrence liên quan.
- Hoàn tất phải qua các quy tắc repository sẵn có: checklist chưa xong hoặc plan còn task mở thì báo lý do và dẫn vào chi tiết.
- Chỉ đóng card sau khi thao tác lưu thành công; khi lỗi vẫn giữ nội dung và cho thử lại. Vô hiệu hóa nút khi đang xử lý để chống click lặp.
- Không cam kết phủ lên màn hình khóa, UAC hoặc ứng dụng toàn màn hình độc quyền. Khi khóa phiên, giữ hàng đợi; lúc mở khóa hiển thị bản tổng hợp.

### 3.3. Trang Hôm nay

Thêm chế độ xem **Hôm nay** cạnh board, lọc được theo dự án hoặc tất cả dự án:

- Các nhóm: Quá hạn, Đến hạn hôm nay, Nhắc hôm nay, Bị chặn, Đã hoàn tất hôm nay. Một ticket có thể xuất hiện ở nhiều nhóm nhưng số tổng phải đếm ID duy nhất.
- Sắp theo giờ đến hạn rồi priority; hiển thị lần nhắc tiếp theo và snooze còn bao lâu.
- Tiến độ plan = task con `done` / toàn bộ task con chưa archived. Plan không có task con hiển thị “Chưa có task”, không mặc định 100%.
- Checklist task = mục đã tick / tổng mục; không có checklist thì hiển thị trạng thái. Checklist 100% không tự chuyển ticket sang done.
- Khi tổng task thay đổi, phần trăm có thể giảm; không giả lập phần trăm theo thời gian đã trôi qua.

### 3.4. Chạy nền và tùy chọn

- Bật “Tiếp tục nhắc khi đóng cửa sổ” trong cài đặt nhắc hẹn. Lúc bật, giải thích nút X sẽ ẩn AMC xuống tray; khi tắt giữ hành vi thoát hiện có.
- Tray có Mở AMC, Hôm nay, Tạm ngưng nhắc, Tiếp tục nhắc, Thoát hoàn toàn. Nhãn cho biết bộ nhắc đang hoạt động hay gặp lỗi.
- “Khởi động cùng Windows” là tùy chọn do người dùng bật, mặc định tắt; không tự thay đổi cấu hình máy trong quá trình triển khai.
- Giờ yên lặng mặc định tắt, âm thanh mặc định tắt. Giờ yên lặng và tạm ngưng vẫn ghi nhận các lịch đến hạn; khi kết thúc gom lại thành một popup.
- Đã thoát hoàn toàn, máy tắt hoặc sleep thì bản đầu không phát popup đúng giờ. Khi runtime chạy lại và phiên được mở khóa, gom các nhắc bị lỡ. UI phải nêu rõ giới hạn này.

## 4. Kiến trúc đề xuất

### 4.1. Một nơi sở hữu dữ liệu và scheduler

Tạo `PlanStudioRuntime` cấp ứng dụng trên Windows, sở hữu repository, scheduler và luồng sự kiện thay đổi. Khởi tạo bất đồng bộ sau khi shell sẵn sàng, quét lịch ngay cả khi chưa mở Plan Studio. Lỗi DB chỉ làm module/nhắc hẹn báo lỗi và dừng scheduler, không làm hỏng các tính năng release khác.

Board/editor dùng repository từ runtime; khi đóng route chỉ dispose controller/subscription, không đóng DB. Giữ injection repository cho các test đang có. Chỉ runtime chính ghi dữ liệu; cửa sổ popup gửi command rồi nhận snapshot kết quả. Dùng single-instance guard trên Windows để mở AMC lần hai không sinh scheduler thứ hai.

Các command sửa ticket mang `itemId`, `expectedRevision`, `commandId`. Backend từ chối snapshot cũ và trả dữ liệu mới; không tự ghi đè draft editor đang autosave. Giữ draft và báo xung đột để người dùng reload/đối chiếu. Lệnh snooze/ack kiểm tra revision occurrence, không làm tăng revision ticket chỉ vì popup vừa hiện.

### 4.2. Cửa sổ Windows

Ưu tiên UI Flutter trong cửa sổ phụ, bridge Windows chịu trách nhiệm show/hide/topmost, tray và sự kiện hệ điều hành. Thực hiện spike trước khi chọn package đa cửa sổ hay mở rộng runner hiện tại; chưa khóa package/version trong tài liệu này.

Spike cần chứng minh: popup vẫn hiện khi main window thu nhỏ/ẩn; không bị quan hệ owner làm ẩn theo main window; không cướp focus; tương tác được; đóng popup không thoát process; chuyển dữ liệu hai chiều; chạy từ bộ Windows release đóng gói đầy đủ.

Nếu dùng Flutter engine phụ, nhánh popup chỉ khởi tạo renderer/theme/bridge, không chạy lại `AppBinding`, Firebase, migration hay scheduler. Cần giữ nhánh `runWebViewTitleBarWidget` hiện có hoạt động bình thường.

Windows hỗ trợ cửa sổ topmost và tùy chọn không activate qua `SetWindowPos`; đây là cơ sở cho hướng thiết kế, vẫn cần kiểm chứng thực tế với Flutter host. Tham khảo [Microsoft: SetWindowPos](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos).

### 4.3. Ranh giới file dự kiến

Các đường dẫn dưới đây tương đối với `lib/app/modules/plan_studio/`:

| File/thành phần | Trách nhiệm |
|---|---|
| `models/work_item.dart` | Thêm `dueAtUtc` nullable, đọc JSON cũ với giá trị mặc định |
| `models/plan_reminder.dart` | Cấu hình nhắc, occurrence, trạng thái và serialization |
| `repositories/plan_repository.dart`, `local_plan_repository.dart` | Migration, thao tác nguyên tử, truy vấn lịch, backup |
| `services/plan_studio_runtime.dart` | Sở hữu dữ liệu, serialize command, phát sự kiện |
| `services/reminder_scheduler.dart` | Tính lịch đến hạn, khôi phục, dedupe; inject clock/timer để test |
| `services/reminder_window_service.dart` | Interface desktop popup, bridge và fake phục vụ test |
| `services/plan_progress_service.dart` | Công thức tiến độ dùng chung board/popup/Hôm nay |
| `views/reminder_popup_view.dart`, `views/today_view.dart` | UI popup và danh sách hôm nay |
| `widgets/reminder_schedule_editor.dart` | Form deadline, giờ nhắc và validation |

Điểm tích hợp ngoài module: `lib/main.dart`, `lib/app/bindings/app_binding.dart`, command palette, theme và `windows/runner/`. Thư viện Windows phải được guard theo nền tảng để không ảnh hưởng Android remote.

## 5. Dữ liệu, migration và độ tin cậy

### 5.1. Schema dự kiến

Giữ ticket JSON, thêm `dueAtUtc` tùy chọn. SQLite nâng schema **1 → 2**:

- `reminders`: `id`, `item_id`, `kind` (absolute/before_due), `scheduled_at_utc`, `offset_minutes`, `enabled`, `revision`, timestamps. Mốc tương đối được tính lại khi đổi deadline.
- `reminder_occurrences`: `id`, `reminder_id`, `schedule_revision`, `scheduled_at_utc`, `eligible_at_utc`, `state`, `snoozed_until_utc`, `presented_at_utc`, `acknowledged_at_utc`, `lease_until_utc`.
- UNIQUE trên `(reminder_id, schedule_revision, scheduled_at_utc)`; index `(state, eligible_at_utc)` để tìm lịch đến hạn mà không parse toàn bộ JSON mỗi nhịp.
- Trạng thái occurrence: `pending → presenting → presented → acknowledged`; `presented → snoozed → presenting`; bất kỳ trạng thái đang hoạt động nào có thể thành `cancelled` khi lịch không còn hợp lệ.
- Bảng receipt theo `commandId` cho thao tác popup cần chống thực thi lại; command, receipt và cập nhật dữ liệu commit trong một transaction.
- Tùy chọn giao diện/tray lưu preferences; cấu hình lịch và trạng thái đã xử lý lưu SQLite.

Migration chạy transaction, giữ mọi ticket hiện có. Backup JSON v2 chứa tickets, reminders và occurrences; import vẫn đọc v1. Import v2 chỉ thêm lịch của ticket mới thực sự được nhập, không ghi đè lịch của ticket đã có; lịch nhập vào mặc định tạm tắt và được xem lại trước khi bật để tránh popup hàng loạt. Không phục hồi lease/process ownership từ máy khác.

### 5.2. Cách scheduler chạy

1. Sau startup hoặc dữ liệu thay đổi, truy vấn mốc gần nhất và đặt timer; có nhịp đối soát dự phòng 30 giây.
2. Timer chỉ đánh thức scheduler, SQLite quyết định occurrence nào còn hợp lệ. Mục tiêu độ trễ khi máy đang thức là tối đa 5 giây trong kiểm thử tải bình thường, không phải cam kết realtime của hệ điều hành.
3. Claim occurrence bằng transaction/lease, kiểm tra lại ticket chưa done/archived và lịch chưa bị thay thế; chuyển payload tới popup.
4. Popup xác nhận đã render rồi mới ghi `presented`. Crash giữa claim/render được phục hồi khi lease hết; occurrence đã hiện nhưng chưa được xử lý được đưa lại vào hàng đợi khi restart.
5. Đảm bảo thao tác idempotent, không hứa “hiện đúng một lần” xuyên crash: có thể hiện lại nhắc chưa xác nhận, nhưng không lặp thao tác và không tạo nhiều cửa sổ cho cùng occurrence.
6. Khi app khởi động lại, resume, unlock hoặc giờ hệ thống đổi: tính lại timer, đối soát và gom nhắc bị lỡ. Chỉ hiện UI khi phiên tương tác sẵn sàng.

Windows có tín hiệu resume qua `WM_POWERBROADCAST`, nhưng resume không đồng nghĩa có người dùng trước màn hình; cần phân biệt với unlock/session active. Tham khảo [Microsoft: PBT_APMRESUMEAUTOMATIC](https://learn.microsoft.com/en-us/windows/win32/power/pbt-apmresumeautomatic).

### 5.3. Quy tắc vòng đời

| Tình huống | Hành vi cần có |
|---|---|
| Snooze 10 phút | Ghi thời điểm mới trước khi đóng card; giữ sau restart; không thay deadline |
| Đã xem / X | Acknowledge occurrence hiện tại; không ngầm hẹn lại; các mốc tương lai khác vẫn còn |
| Done / archive / delete | Hủy lịch còn hoạt động và loại khỏi popup trong cùng luồng cập nhật |
| Reopen / restore | Giữ cấu hình để xem lại nhưng không tự bật lịch cũ đã quá giờ; người dùng đặt lại |
| Đổi deadline/lịch | Tăng revision lịch, hủy occurrence cũ chưa xử lý và sinh lịch mới; lịch absolute không đổi theo deadline |
| Xóa plan | Hủy lịch của plan; task con vẫn giữ lịch riêng theo hành vi giữ task hiện tại |
| Nhiều nhắc bị lỡ | Một cửa sổ tổng hợp, nhóm theo ticket; giữ giờ hẹn gốc và thông tin bị lỡ |
| Mất màn hình ngoài | Khôi phục popup vào work area của màn hình còn lại |
| Ghi DB thất bại | Không báo thành công, không đóng card; scheduler tránh retry dồn dập |

Thời điểm một lần lưu UTC; nhập/hiển thị theo timezone máy. Đổi timezone không đổi thời điểm tuyệt đối đã lưu; UI cập nhật giờ địa phương. Khi làm lịch lặp giai đoạn sau, phải thêm IANA timezone và quy tắc DST trước khi phát hành, không dùng cộng cố định 24 giờ cho lịch “mỗi ngày lúc 9h”.

## 6. Backlog và thứ tự triển khai

Mã PSR dưới đây chỉ là mã kế hoạch trong tài liệu, chưa tạo ticket trong DB thật. Ước lượng cho một lập trình viên quen Flutter/Windows; cần điều chỉnh sau spike.

| Mã | Công việc và đầu ra nghiệm thu | Phụ thuộc | Ước lượng |
|---|---|---|---|
| PSR-01 | Spike popup Flutter/Windows + IPC + tray; demo từ release build, main ẩn mà popup vẫn hiện, không cướp focus | — | 1–2 ngày |
| PSR-02 | Runtime cấp app, shared repository, change stream, single-instance, xử lý xung đột editor | PSR-01 | 1–2 ngày |
| PSR-03 | Model, migration v2, repository reminder/occurrence, import/export v1/v2, transaction cancel | PSR-02 | 1–2 ngày |
| PSR-04 | Editor deadline/nhắc, validation, badge board, thử popup | PSR-03 | 1 ngày |
| PSR-05 | Scheduler bền vững, dedupe, snooze, startup/resume/unlock, hàng đợi | PSR-03 | 1–2 ngày |
| PSR-06 | Popup thật với tiến độ, hành động, deep link mở đúng ticket, đồng bộ theme và lỗi | PSR-01, 02, 04, 05 | 1–2 ngày |
| PSR-07 | Tray, cài đặt chạy nền/autostart, tạm ngưng và giờ yên lặng | PSR-05, 06 | 1–2 ngày |
| PSR-08 | Hôm nay, tiến độ dùng chung, lọc/sắp xếp và số đếm | PSR-02, 03 | 1 ngày |
| PSR-09 | Regression, test máy thật, đóng gói release, cập nhật README | PSR-04 đến 08 | 1–2 ngày |

Tổng bản đầu dự kiến **9–16 ngày công**, chưa gồm lịch lặp, widget ghim hoặc đồng bộ. PSR-01 là điểm kiểm chứng bắt buộc: nếu phương án cửa sổ không đạt, thay cách host và cập nhật ước lượng trước khi triển khai phần UI còn lại.

Mốc demo sớm: đặt lịch → ẩn AMC → popup xuất hiện → snooze → đóng/mở app → lịch snooze vẫn đúng. Sau đó hoàn thiện Hôm nay và các tình huống lỗi để phát hành.

## 7. Kiểm thử và tiêu chí phát hành

**Tự động:**

- Migration DB v1 thật sang v2 không mất ticket, sequence, revision và lịch sử; import/export v1/v2, rollback khi dữ liệu lỗi, không kích hoạt lịch import ngoài ý muốn.
- Fake clock: đến hạn, snooze, giờ yên lặng qua nửa đêm, nhiều occurrence cùng giờ, chỉnh giờ tiến/lùi, restart phục hồi lease và nhắc chưa xử lý.
- Repository: hoàn tất/archive/delete đồng thời timer đến hạn; hai command cùng ID; đổi lịch khi popup đang mở; plan cha/task con; revision conflict với autosave.
- Widget: nội dung popup và hành động, pending/error, danh sách hàng đợi, progress dùng chung, thời gian local, text scale lớn và cửa sổ nhỏ.
- Chạy lại các test Plan Studio hiện có, `flutter analyze`, build Windows release; build Android debug để phát hiện phụ thuộc Windows lọt vào startup mobile.

**Máy Windows thật:**

1. Đặt nhắc sau một phút, chuyển sang ứng dụng khác và gõ: popup hiện theo mục tiêu độ trễ, bàn phím vẫn ở ứng dụng đang gõ.
2. Đóng màn Plan Studio, thu nhỏ AMC, ẩn tray: cả ba tình huống vẫn nhắc; mở AMC lần hai không nhân đôi lịch.
3. Snooze rồi restart: đúng một mục nhắc đang chờ, không mất lịch; kill app ngay quanh thời điểm render không mất occurrence.
4. Sleep/hibernate và khóa màn hình qua giờ hẹn: unlock nhận một popup tổng hợp, không tràn cửa sổ.
5. Hoàn tất checklist, hoàn tất task hoặc cập nhật blocked từ popup: board/editor phản ánh dữ liệu mới; bản nháp đang sửa không bị ghi đè âm thầm.
6. Nhiều màn hình, DPI 100/150/200%, rút màn hình ngoài, hai theme hiện có: không cắt nút hoặc mất popup.
7. Thoát hoàn toàn dừng process; chạy lại khôi phục nhắc lỡ; nút X tuân theo cài đặt chạy nền. Thử trên bản release được copy sang thư mục sạch.
8. Tray/popup hoạt động không cần Internet; lỗi mở DB không làm AMC mất các chức năng khác.

Chỉ đánh dấu hoàn tất bản đầu khi luồng nhắc ngoài cửa sổ chính, persistence và QA Windows thực tế đã qua; widget test đơn thuần không đủ kiểm chứng hành vi cửa sổ desktop.

## 8. Phát triển tiếp sau bản đầu

- **Nhắc lặp:** mỗi ngày/tuần, chọn ngày làm việc và giờ; bỏ qua các kỳ bị lỡ thay vì phát lại toàn bộ; completion kết thúc chuỗi, không tự tạo task mới.
- **Check-in tiến độ:** nhắc cập nhật task đang làm/blocked theo giờ người dùng chọn; dựa vào lần cập nhật nội dung/trạng thái thực, không dựa vào `updatedAt` bị thay đổi bởi reorder.
- **Bảng tiến độ ghim:** cửa sổ thu gọn cho một plan, đồng bộ cùng nguồn dữ liệu popup; xem việc tiếp theo và mở nhanh ticket.
- **Tổng kết tuần:** số task hoàn tất, quá hạn, bị chặn, lịch sử dời hẹn; cần bổ sung mốc lịch sử deadline nếu muốn đánh giá “hoàn tất đúng hạn” đáng tin cậy.

Ưu tiên triển khai PSR-01 → PSR-07 trước để giải quyết trực tiếp nhu cầu popup nhắc hẹn, sau đó hoàn thiện PSR-08 và PSR-09 cho bản phát hành đầu.
