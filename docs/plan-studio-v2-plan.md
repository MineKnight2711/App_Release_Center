# Kế hoạch nâng cấp Plan Studio v2 — Giao diện mới và Deadline

Ngày: 2026-09-28. Trạng thái: **đã chốt mục 9; GĐ1 và GĐ2 (PS2-01 → PS2-09) đã xong. GĐ3 (Lịch, Hôm nay, popup dời hạn, tóm tắt sáng) để sau.**

## Tiến độ

- **PS2-01:** `theme/studio_tokens.dart` lấy màu trạng thái, hạn, ưu tiên từ `AppPalette`; bỏ hex cứng. `TicketCard` tách sang `widgets/ticket_card.dart`. Hàng số liệu cũ (và lỗi đếm Bị chặn hai lần) được thay bằng thanh chỉ số.
- **PS2-02:** `dueAllDay`, `dueHistory`, getter `dueAt`; `services/deadline.dart` (trạng thái, nhãn, preset, rollup plan). Repository ghi activity Đặt/Dời/Bỏ hạn và lịch sử dời. Nhắc trước hạn của hạn cả ngày tính từ 9:00 sáng ngày hạn; đổi kiểu hạn cũng dời lịch nhắc tương đối.
- **PS2-03:** `DeadlineChip`, `DeadlinePicker` (preset, lịch tháng tự vẽ tiếng Việt, “Có giờ”, nhắc trước hạn) trong popover neo theo vị trí.
- **PS2-04:** Card mới: viền trái P0/P1, chip hạn/nhắc/tiến độ/note, callout bị chặn, ⋯ khi hover, menu chuột phải có Đặt/Sửa/Bỏ hạn.
- **PS2-05:** Thanh công cụ một hàng (hai hàng khi < 900px), chọn dự án dạng menu, tìm `/`, nút Tạo tách loại, ⋯ gom backup; thanh chỉ số bấm để lọc; chip lọc Loại/Ưu tiên/Nhãn/Hạn/Sắp/Lưu trữ; thu gọn cột (nhớ theo dự án).
- **Làm sớm từ GĐ2:** tạo nhanh inline trong cột (chưa có cú pháp `^mai`); dialog Tạo mới có Hạn, Enter/Ctrl+Enter; ô Hạn ở tab Chi tiết của panel và tab Nhắc hẹn; phím `N` tạo task.
- **PS2-06:** Panel chi tiết chia 2 vùng. Bên trái là tiêu đề sửa tại chỗ, nội dung Markdown Viết/Xem (`widgets/markdown_view.dart`, không thêm package), task con, checklist có thanh tiến độ, và một dòng thời gian gộp ghi chú với hoạt động (Ctrl+Enter). Bên phải là cột thuộc tính rộng 290px (Trạng thái, Ưu tiên, Hạn, Nhắc hẹn dạng popover, Nhãn dạng chip có gợi ý, Plan gốc, Dự án). Dưới 820px, cột thuộc tính chuyển lên dưới tiêu đề. Tab còn Chi tiết · Soạn plan · Phiên bản (chỉ với plan). Copy, xuất, lưu trữ và xóa nằm trong menu ⋯; Ctrl+S lưu ngay.
- **PS2-07:** `services/quick_add_parser.dart` hiểu `!p0–!p3`, `#nhãn`, `^hôm nay/^mai/^mốt/^t2–^t7/^cn/^cuối tuần/^tuần sau/^25/10[/2027]`, kèm giờ `17h`, `8h45`, `9:30`, có dấu hay không dấu đều được. Token không hợp lệ được giữ nguyên trong tiêu đề. Ô tạo nhanh trong cột và dialog Tạo mới tô màu token ngay khi gõ và hiện chip kết quả bên dưới.
- **PS2-08:** Cột thuộc tính cảnh báo task có hạn sau plan gốc. Với plan, hiện số task con trễ, số task có hạn sau plan và task gần hạn nhất. “Tạo task từ plan” có tùy chọn dùng hạn của plan.
- **PS2-09:** Bảng lệnh Ctrl+K riêng cho Plan Studio (lệnh, lọc, chuyển dự án, nhảy tới ticket, tìm không dấu). Trên card đang focus: `D` đặt hạn, `1–6` chuyển cột. `?` mở bảng phím tắt; Esc trong ô tìm để xóa.
- **Bổ sung (29/9): đổi tên dự án và chuyển ticket giữa dự án.** Repository có `renameProject` (chỉ đổi tên hiển thị, 1–80 ký tự) và `moveToProject` (một transaction). Plan mặc định chuyển kèm task con; nếu bỏ chọn, task con ở lại và bỏ liên kết. Task chuyển đi thì bỏ liên kết với plan ở dự án cũ. Mã ticket, trạng thái, hạn và nhắc hẹn giữ nguyên; activity ghi “Chuyển dự án: A → B”. “Gắn lại thư mục” từ nay giữ tên đã đặt. Giao diện: đổi tên trong menu chọn dự án, menu ⋯ và bảng lệnh; chuyển dự án từ menu chuột phải/⋯ trên card (kể cả khi xem Tất cả dự án hay Lưu trữ), phím `M`, menu ⋯ và dòng “Dự án” trong panel. Dialog chọn dự án có nút “Thêm dự án…”. Khi xem Tất cả dự án, card hiện kèm tên dự án. Thêm 9 test (5 repository, 4 widget); Plan Studio có 78 test, đều qua.
- Kiểm chứng GĐ2: thêm 14 test (7 parser, 7 widget: tạo nhanh, Ctrl+K, phím trên card, `?`, cột thuộc tính, Markdown/màn hẹp, cảnh báo plan↔task). Plan Studio có 69 test, toàn app 546 test đều qua (trừ `machine_power_service_test.dart` hỏng từ trước). Đã xem ảnh panel, ô tạo nhanh và bảng lệnh ở theme Console và Default.
- Kiểm chứng GĐ1: 14 test mới (logic hạn, repository, widget board); 55 test Plan Studio và 532 test toàn app đều qua. Ngoại lệ duy nhất là `test/machine_power_service_test.dart`, file này hỏng cú pháp từ trước và không liên quan. Đã xem ảnh chụp board ở 3 theme, cùng popover hạn, dialog tạo mới và panel chi tiết.

## 1. Mục tiêu và phạm vi

1. **Giao diện:** board, card, panel chi tiết và luồng tạo ticket gọn hơn, phân cấp rõ, thao tác nhanh bằng bàn phím; ăn theo ba theme AMC (Console, Cyber, Default) qua `AppPalette`, không dùng màu cứng.
2. **Deadline:** biến `dueAtUtc` đang có sẵn thành một tính năng hạng nhất: đặt hạn nhanh ở mọi nơi, trạng thái hạn nhìn là hiểu, lọc/sắp theo hạn, lịch sử dời hạn, quy tắc plan ↔ task, và (giai đoạn sau) góc nhìn Lịch.

Ngoài phạm vi v2: đồng bộ team, start date/Gantt, deadline trên mobile remote, AI tự tách task.

## 2. Hiện trạng đã kiểm tra

Đã đọc toàn bộ `lib/app/modules/plan_studio` (~5.800 dòng) và chụp board qua test `light and dark board visual QA`.

**Deadline đã có (nền tốt, nhưng bị chôn):**

- `WorkItem.dueAtUtc` (UTC, nullable), đọc được dữ liệu cũ.
- Đặt hạn ở tab **Nhắc hẹn → ExpansionTile “Hạn hoàn thành & nhắc trước hạn”** (đang thu gọn, ở cuối form) — cần 3 lần bấm mới thấy.
- Nhắc trước hạn (Đúng hạn / 15 phút / 1 giờ / 1 ngày) qua `ReminderStore.add(offsetMinutes:)`; `reconcile` tự dời lịch khi đổi hạn — **giữ nguyên, tái sử dụng**.
- Card hiện dòng chữ `Hạn · dd/mm/yyyy hh:mm`, đỏ khi quá hạn. Màn Hôm nay có nhóm Quá hạn / Đến hạn hôm nay. Popup nhắc có nhãn “Đã quá hạn”.
- Thiếu: đặt hạn khi tạo ticket, preset nhanh, hạn theo ngày (không giờ), mức “sắp đến hạn”, lọc/sắp theo hạn, lịch sử dời hạn, quan hệ hạn plan ↔ task.

**Vấn đề giao diện quan sát được:**

| # | Vị trí | Vấn đề |
|---|---|---|
| U1 | Header board | ~260px trước khi tới cột: dòng tip cố định, hàng nút, hàng số liệu, hàng lọc, dòng hướng dẫn |
| U2 | Hàng nút | 5–6 nút ngang hàng, không có hành động chính rõ ràng; chip “Lưu trên máy” trông như nút nhưng không bấm được |
| U3 | Số liệu | Trùng với số đếm cột; **bug:** “Đang xử lý” = tổng − chưa xử lý − hoàn tất nên đếm cả Bị chặn lẫn Chờ kiểm tra, Bị chặn bị đếm hai lần (`plan_studio_view.dart:556`) |
| U4 | Bộ lọc | 4 control rời; dropdown Loại hiện tên enum `PLAN/TASK/NOTE` tiếng Anh; lọc nhãn là ô gõ tự do |
| U5 | Card | Ngày góc phải là `updatedAt` nhưng dễ đọc nhầm là hạn; P2 (mặc định) hiện trên mọi card gây nhiễu; menu ⋮ luôn hiện; hạn/nhắc là dòng chữ thường, không nổi |
| U6 | Màu | `statusColor()` là 6 mã hex cứng trong `kanban_column.dart`, không theo theme |
| U7 | Cột | 6 cột rộng cố định 292px, cột trống vẫn chiếm đủ chiều cao; nút + ở mỗi cột nhưng không có tạo nhanh inline |
| U8 | Panel chi tiết | Một form dài: tiêu đề, thẻ “Đặt nhắc hẹn” dẫn sang tab khác, dropdown, nhãn gõ dấu phẩy, nội dung, nút, task con, checklist, note, lưu trữ, xóa (xóa xuất hiện 2 lần); body chỉ là TextField, không xem trước Markdown |
| U9 | Tạo ticket | Dialog chỉ có Loại + Tiêu đề; mọi thuộc tính khác phải mở panel sau khi tạo |
| U10 | Hôm nay | Là route riêng, ListTile ba dòng dày chữ, không thao tác nhanh được (hoàn tất, dời hạn) |

## 3. Nguyên tắc thiết kế

Tham chiếu “taste” của các công cụ task hiện đại (Linear, Things 3, Height, Todoist):

- **Một hành động chính mỗi vùng.** Board: “+ Tạo”. Panel: nội dung. Mọi thứ khác ở mức phụ hoặc trong menu ⋯.
- **Thuộc tính là “property”, không phải form.** Trạng thái, ưu tiên, hạn, nhắc, nhãn… hiển thị dạng hàng thuộc tính, bấm mở popover chỉnh — không dropdown dạng form.
- **Tiết lộ dần.** Tip và hướng dẫn chuyển vào empty state, tooltip, placeholder; không chiếm chỗ thường trực.
- **Màu mang nghĩa.** Chỉ dùng màu cho trạng thái, hạn và ưu tiên cao; còn lại trung tính. Tất cả lấy từ token.
- **Nhịp 4/8pt, bo góc 3 bậc** (6 chip · 10 card · 14 panel), số và giờ dùng `FontFeature.tabularFigures()`.
- **Bàn phím trước.** `N` tạo, `/` tìm, `D` đặt hạn, `Enter` mở, `1–6` chuyển trạng thái, `Esc` đóng; tích hợp Ctrl+K sẵn có của AMC.
- **Chuyển động ngắn** 120–200ms, `easeOutCubic`; không animation trang trí.
- **Truy cập:** tương phản AA ở cả 3 theme, focus ring rõ, không phụ thuộc màu (luôn kèm icon/chữ), text scale 1.3 không vỡ.

## 4. Thiết kế giao diện mới

### 4.1 Khung board

```
┌───────────────────────────────────────────────────────────────────────────────┐
│ Plan Studio  [Mobile App ▾]   [Board | Danh sách | Lịch]   [🔍 Tìm…  /]  [+ Tạo ▾] ⋯ │  56px
│ ⚠ 2 quá hạn · ◷ 3 đến hạn tuần này · ⛔ 1 bị chặn      [Loại ▾][Ưu tiên ▾][Nhãn ▾][Hạn ▾][Sắp: Thủ công ▾] │  40px
├───────────────────────────────────────────────────────────────────────────────┤
│ ● Chưa xử lý 2 │ ● Sẵn sàng 1 │ ● Đang làm 1 │ ● Bị chặn 1 │ ● Chờ KT 1 │ ▸ Hoàn tất 4 │
│  …cards…       │              │              │             │            │ (thu gọn)    │
│  + Thêm task   │  + Thêm task │              │             │            │              │
```

- **Thanh trên (56px):** chọn dự án (kèm “Thêm dự án” trong dropdown), segmented chọn góc nhìn, ô tìm (`/`), nút chính **+ Tạo** dạng split (Task · Plan bằng AI · Note), menu ⋯ (backup, nhập Markdown, gắn lại thư mục, cài đặt nhắc hẹn, xem lưu trữ).
- **Thanh sức khỏe + lọc (40px):** thay hàng số liệu trùng lặp bằng 3 chỉ số có ý nghĩa — Quá hạn, Đến hạn 7 ngày, Bị chặn; **bấm vào là lọc**. Bộ lọc dạng chip, khi có giá trị thì chip đổi màu và có nút ×; “Xóa lọc” khi ≥1 lọc.
- Bỏ dòng tip và dòng hướng dẫn kéo thả; trạng thái “đang lọc nên không sắp được” hiện bằng tooltip trên tay nắm kéo.
- **Cột:** header dính (sticky), số đếm; cột Hoàn tất và cột trống có thể **thu gọn thành rail 44px** (nhớ theo dự án); ô **“+ Thêm task” inline** cuối cột: gõ tiêu đề, Enter tạo, hỗ trợ cú pháp nhanh (4.5).
- Góc nhìn **Danh sách:** bảng gọn nhóm theo trạng thái hoặc theo hạn, sắp theo cột — dành cho khi nhiều ticket.

### 4.2 Card

```
┌──────────────────────────────┐
│▌ ☐ MPS-012              ⋯   │  ⋯ chỉ hiện khi hover/focus; ▌ viền trái màu = P0/P1
│  Kết nối cổng thanh toán     │  tiêu đề ≤2 dòng, đậm
│  ⛔ Chờ tài khoản sandbox     │  callout lý do (chỉ khi bị chặn)
│  [⚑ Trễ 2 ngày] [⏰ 17:00] ☑ 2/5  💬3 │  hàng meta: chip hạn, nhắc, checklist, note
│  Mobile · UX +1              │  tối đa 2 nhãn + số còn lại
└──────────────────────────────┘
```

- Bỏ ngày `updatedAt`; bỏ mô tả body (chỉ giữ cho Note); P2/P3 không hiện, P0/P1 là viền trái + icon cờ.
- **Chip hạn** là thành phần chính của hàng meta (xem 5.2). Plan hiện vòng tiến độ nhỏ `3/5` thay thanh ngang.
- Hover: nâng nhẹ + hiện ⋯; focus bàn phím có ring. Menu ⋯/chuột phải: Đổi trạng thái, **Đặt hạn**, Nhắc hẹn, Ưu tiên, Lưu trữ.

### 4.3 Panel chi tiết (2 vùng)

```
┌─ MPS-012 · Task ───────────────── Đã lưu ✓   ⋯   ✕ ┐
│ Kết nối cổng thanh toán (tiêu đề lớn, sửa tại chỗ) │ Trạng thái  ● Bị chặn    │
│                                                     │ Ưu tiên     ⚑ P0         │
│ [Viết | Xem]  Nội dung Markdown…                    │ Hạn         Thứ 6, 3/10  │
│                                                     │ Nhắc hẹn    2 lịch       │
│ Checklist 2/5 ▢ … ▢ …  + Thêm                       │ Nhãn        Mobile  +    │
│ Task con (plan)                                     │ Plan gốc    MPS-001      │
│ Hoạt động & ghi chú (một dòng thời gian chung)      │ Dự án       Mobile App   │
│ [Viết ghi chú…]                                     │                           │
└─────────────────────────────────────────────────────┴───────────────────────────┘
```

- Rộng 960px (≥1280) với rail thuộc tính 260px bên phải; <1100px rail chuyển thành lưới thuộc tính ở đầu.
- Tab còn: **Chi tiết · Soạn plan (chỉ plan) · Phiên bản (chỉ plan)**. Nhắc hẹn không còn là tab riêng: dòng “Nhắc hẹn” trong rail mở popover chứa `ReminderScheduleEditor` đã rút gọn.
- Nhãn là chip input có gợi ý từ nhãn đã dùng trong dự án. Note và activity gộp thành một timeline.
- Xóa, Lưu trữ, Xuất Markdown, Copy vào menu ⋯ đầu panel. Trạng thái lưu hiển thị nhỏ cạnh tiêu đề; bỏ nút “Lưu ngay” (vẫn giữ Ctrl+S).

### 4.4 Tạo ticket

Thay `_CreateTicketDialog` bằng **composer** gọn: loại (segmented), tiêu đề, hàng chip thuộc tính `[Hạn] [Ưu tiên] [Nhãn] [Plan gốc] [Trạng thái]`. `Enter` tạo, `Ctrl+Enter` tạo và mở panel. Plan AI vẫn mở thẳng tab Soạn plan.

### 4.5 Cú pháp nhanh (quick-add và composer)

`Sửa lỗi thanh toán !p1 #mobile ^mai 17h` → P1, nhãn `mobile`, hạn ngày mai 17:00. Hỗ trợ: `^hôm nay`, `^mai`, `^t2…^cn`, `^tuần sau`, `^25/10`, `^25/10 9h30`. Phần nhận diện được tô sáng ngay trong ô gõ; không nhận diện được thì giữ nguyên trong tiêu đề.

### 4.6 Token theo theme

`StudioTokens` (ThemeExtension) dựng từ `AppPalette`: màu 6 trạng thái (idle, info, accentAlt, danger, warning, success), màu hạn (neutral/warning/danger/success), bán kính, khoảng cách, style chữ. `statusColor()` đọc token thay cho hex cứng.

## 5. Tính năng Deadline

### 5.1 Mô hình dữ liệu (tương thích ngược)

Thêm vào payload JSON của `WorkItem`, tất cả **tùy chọn** khi đọc:

| Trường | Kiểu | Ý nghĩa |
|---|---|---|
| `dueAtUtc` | giữ nguyên | Thời điểm hạn (UTC) |
| `dueAllDay` | `bool`, mặc định `false` | Hạn theo ngày: lưu 23:59 giờ local của ngày đó, hiển thị không kèm giờ; nhắc “đúng hạn” mặc định 9:00 sáng ngày đó |
| `dueHistory` | `List<{from, to, at}>` | Lịch sử dời hạn, ghi khi đổi hạn đã có (không ghi khi đặt lần đầu) |

Thêm getter `DateTime? get dueAt` để thôi `DateTime.parse` rải rác trong build. `_touch` ghi activity “Đặt hạn …/Dời hạn … → …/Bỏ hạn”. Không cần tăng `schemaVersion` của backup vì trường mới nằm trong payload và bản cũ bỏ qua khóa lạ; test import backup v3 cũ vẫn phải qua.

### 5.2 Trạng thái hạn — `services/deadline.dart`

Hàm thuần `DueState dueState(WorkItem, DateTime now)`, test bằng đồng hồ giả:

| Trạng thái | Điều kiện | Chip |
|---|---|---|
| `none` | không có hạn | ẩn |
| `later` | > 7 ngày | trung tính · “12/10” |
| `thisWeek` | ≤ 7 ngày | trung tính đậm · “Thứ 6” |
| `soon` | ≤ 24 giờ hoặc ngày mai | cảnh báo · “Mai 17:00” / “Còn 3 giờ” |
| `today` | hôm nay, chưa qua | cảnh báo đậm · “Hôm nay 17:00” / “Hôm nay” |
| `overdue` | đã qua, chưa xong | nguy hiểm · “Trễ 2 ngày” / “Trễ 3 giờ” |
| `doneOnTime` / `doneLate` | đã xong, so `completedAt` | thành công / tắt · “Đúng hạn” / “Trễ 1 ngày” |

Nhãn tương đối và tuyệt đối trong một hàm dùng chung cho card, danh sách, popup, Hôm nay. Tooltip chip luôn hiện ngày giờ đầy đủ.

### 5.3 Bộ chọn hạn — `widgets/deadline_picker.dart`

Popover dùng chung ở card, rail, composer, bàn phím `D`:

- **Preset:** Hôm nay · Ngày mai · Thứ 6 này · Tuần sau (T2) · +1 tuần · Bỏ hạn.
- Lịch tháng nhỏ (tuần bắt đầu Thứ 2), công tắc **“Có giờ”** (mặc định tắt), giờ gợi ý 9:00 · 12:00 · 17:00 · tùy chỉnh.
- **Nhắc trước hạn** ngay bên dưới: ô chọn Đúng hạn · 15 phút · 1 giờ · 1 ngày → gọi `reminders.add(offsetMinutes:)` sẵn có (giới hạn 3 lịch giữ nguyên).
- Chọn ngày trong quá khứ: cho phép nhưng hiện cảnh báo “Hạn đã qua”.

### 5.4 Board và bộ lọc

- Chip lọc **Hạn:** Quá hạn · Hôm nay · 7 ngày tới · Không có hạn.
- **Sắp xếp trong cột:** Thủ công (mặc định, cho kéo sắp) · Theo hạn · Theo ưu tiên. Khi không phải Thủ công thì chỉ cho kéo đổi cột, giống quy tắc khi đang lọc.
- Thanh sức khỏe (4.1) lấy số từ `dueState`.

### 5.5 Plan ↔ Task

- Card plan hiện **hạn gần nhất chưa xong** của task con khi plan chưa có hạn riêng, và badge “1 task trễ” nếu có.
- Task có hạn sau hạn của plan gốc: **cảnh báo** trong rail (không chặn lưu).
- “Tạo task từ plan”: tùy chọn “Dùng hạn của plan cho các task”.

### 5.6 Dời hạn và theo dõi

- Đổi hạn đã có → ghi `dueHistory` + activity. Rail hiện “Đã dời 2 lần” (bấm xem lịch sử).
- Popup nhắc hạn (`reminder_popup_view.dart`) thêm nút **Dời hạn** (+1 ngày · Thứ 6 · Tuần sau) bên cạnh snooze; dời hạn đi qua repository để `reconcile` dời lịch nhắc tương đối.

### 5.7 Góc nhìn Lịch (giai đoạn 3)

Lưới tháng + danh sách tuần; ticket theo ngày hạn; **kéo sang ngày khác để dời hạn** (giữ giờ nếu có); khay bên trái “Quá hạn” và “Chưa có hạn” để kéo vào lịch.

### 5.8 Tóm tắt buổi sáng (giai đoạn 3, tùy chọn)

Trong Cài đặt nhắc hẹn: bật “Tóm tắt hạn mỗi ngày lúc 8:30” → một popup qua runtime nhắc hẹn hiện có: “2 quá hạn · 3 đến hạn hôm nay”, bấm mở Hôm nay. Mặc định tắt.

## 6. Ranh giới code

| File | Thay đổi |
|---|---|
| `models/work_item.dart` | `dueAllDay`, `dueHistory`, getter `dueAt`, validate khi đọc |
| `services/deadline.dart` *(mới)* | `DueState`, nhãn tương đối, preset, parser cú pháp nhanh |
| `theme/studio_tokens.dart` *(mới)* | ThemeExtension từ `AppPalette` |
| `widgets/ticket_card.dart` *(tách từ kanban_column)* | Card mới |
| `widgets/deadline_chip.dart`, `widgets/deadline_picker.dart` *(mới)* | Chip và popover hạn |
| `widgets/studio_toolbar.dart`, `widgets/filter_bar.dart` *(mới)* | Thanh trên, sức khỏe, chip lọc |
| `widgets/quick_add.dart` *(mới)* | Tạo inline + composer |
| `widgets/kanban_column.dart` | Header sticky, thu gọn cột, quick-add; bỏ `statusColor` hex |
| `views/plan_studio_view.dart` | Dựng lại bằng toolbar/filter; state lọc/sắp tách thành `PlanBoardFilter` trong controller |
| `views/ticket_editor.dart` → `views/editor/` | Tách `ticket_main_pane.dart`, `ticket_properties_rail.dart`; file hiện 1.035 dòng |
| `views/today_view.dart` | Thành góc nhìn trong Plan Studio, card có tick hoàn tất và dời hạn |
| `views/calendar_view.dart` *(mới, GĐ3)* | Lịch tháng/tuần |
| `repositories/local_plan_repository.dart` | Activity cho hạn, ghi `dueHistory` trong `_touch` |
| `views/reminder_popup_view.dart` | Nút Dời hạn |

## 7. Backlog triển khai

| ID | Nội dung | Phụ thuộc | Ước lượng |
|---|---|---|---|
| **GĐ1 — Nền và Deadline cốt lõi** ||||
| PS2-01 | `StudioTokens`, màu trạng thái theo theme, tách `TicketCard`, sửa bug đếm U3 | — | 0,5–1 ngày |
| PS2-02 | Model hạn (`dueAllDay`, `dueHistory`, `dueAt`), activity, `deadline.dart` + test đồng hồ giả | — | 1 ngày |
| PS2-03 | `DeadlineChip` + `DeadlinePicker` (preset, lịch, có giờ, nhắc trước hạn) | 01, 02 | 1–1,5 ngày |
| PS2-04 | Card mới + menu ngữ cảnh “Đặt hạn” | 01, 03 | 1 ngày |
| PS2-05 | Toolbar, thanh sức khỏe, chip lọc (gồm Hạn), sắp theo hạn/ưu tiên, thu gọn cột | 01, 02 | 1,5 ngày |
| **GĐ2 — Panel và tạo nhanh** ||||
| PS2-06 | Panel 2 vùng + rail thuộc tính, nhắc hẹn dạng popover, Markdown Viết/Xem, timeline note | 03 | 2–3 ngày |
| PS2-07 | Composer tạo mới + quick-add inline + parser cú pháp nhanh | 02, 03 | 1,5 ngày |
| PS2-08 | Quy tắc plan ↔ task (hạn gần nhất, badge trễ, cảnh báo, kế thừa khi tạo task) | 02, 06 | 1 ngày |
| PS2-09 | Phím tắt board/panel, điều hướng focus, lệnh Ctrl+K | 04–07 | 1 ngày |
| **GĐ3 — Góc nhìn** ||||
| PS2-10 | Hôm nay thành góc nhìn trong Studio + Danh sách; thao tác nhanh | 04, 05 | 1–1,5 ngày |
| PS2-11 | Lịch tháng/tuần, kéo để dời hạn, khay quá hạn/chưa có hạn | 03, 10 | 2–3 ngày |
| PS2-12 | Nút Dời hạn trên popup + tóm tắt buổi sáng (tùy chọn) | 02 | 1 ngày |
| PS2-13 | QA: ảnh 3 theme × sáng/tối, cửa sổ 1280/1920, text scale 1.3, 200 ticket, regression, analyze, build release | tất cả | 1 ngày |

Tổng **~15–20 ngày công**. GĐ1 đã tự đứng được (có giá trị ngay: deadline dễ đặt, dễ thấy, lọc được), nên có thể phát hành sau GĐ1 rồi làm tiếp.

## 8. Kiểm thử và tiêu chí nghiệm thu

- `deadline.dart`: mọi ranh giới `DueState` (đúng 24h, qua nửa đêm, hạn cả ngày, xong trước/sau hạn), nhãn tiếng Việt, parser cú pháp nhanh (hợp lệ, mơ hồ, không nhận diện).
- Repository: đọc ticket/backup v1–v3 không có trường mới; dời hạn ghi `dueHistory` + dời nhắc tương đối trong cùng transaction; bỏ hạn hủy nhắc tương đối (test hiện có vẫn qua).
- Widget: board 3 theme không overflow ở 1280px; card hover/focus; picker chọn preset → chip đúng; lọc Quá hạn đúng số với thanh sức khỏe; sắp theo hạn tắt kéo sắp.
- Chạy lại toàn bộ `test/plan_studio_*`, `flutter analyze`, build Windows release. Xem ảnh chụp QA (`STUDIO_SCREENSHOTS`) trước khi đóng mỗi giai đoạn.

## 9. Câu hỏi cần chốt

| # | Câu hỏi | Đề xuất |
|---|---|---|
| Q1 | Hạn mặc định là **theo ngày** (không giờ) hay luôn có giờ? | Theo ngày, bật “Có giờ” khi cần |
| Q2 | Giữ 6 cột hay rút còn 4 (gộp Sẵn sàng → Chưa xử lý, Chờ kiểm tra → Đang làm)? | Giữ 6, cho thu gọn cột |
| Q3 | Góc nhìn Lịch làm trong đợt này hay để sau? | Để GĐ3, sau khi GĐ1–2 ổn |
| Q4 | Mã ticket giữ tiền tố chung `MPS-` hay theo từng dự án (vd `APP-012`)? | Giữ `MPS-` ở v2 (đổi là thay đổi dữ liệu) |
| Q5 | Tóm tắt buổi sáng: làm không, mặc định bật hay tắt? | Làm, mặc định tắt |
| Q6 | Thứ tự ưu tiên: UI trước hay Deadline trước? | Đan xen theo GĐ1 như trên — deadline là phần “nhìn thấy” đầu tiên của UI mới |
