# Kế hoạch tích hợp Mobile Plan Studio và bảng ticket

Ngày: 2026-09-18. Trạng thái: đã triển khai bản đầu; nội dung bên dưới giữ lại thiết kế và backlog gốc để đối chiếu.

## Tiến độ triển khai

- Đã có module độc lập `lib/app/modules/plan_studio`, mở từ panel Dự án hoặc command palette. Repository được mở khi vào module, không thêm phụ thuộc khởi tạo vào các luồng release/Android remote.
- Đã có SQLite transaction, project UUID, Plan/Task/Note, tự lưu, board sáu cột, kéo thả/reorder/auto-scroll, menu thay thế, tìm/lọc, note/checklist/lịch sử và archive/restore.
- Đã port Ollama local, lưu câu trả lời và phiên bản plan; hủy phản hồi muộn, retry, phục hồi bản cũ; tạo task thủ công từ plan với chống trùng.
- Đã có xuất/nhập JSON, nhập/xuất Markdown và gắn lại path dự án. Import chỉ thêm ID mới, không ghi đè bản cũ; xung đột dự án hủy transaction.
- UI thực tế dùng board toàn màn hình và tab Soạn plan trong panel chi tiết bên phải. Đồng bộ team, AI tự tách task và chạy agent vẫn ngoài phạm vi bản đầu.
- Kiểm chứng: toàn bộ 318 test sau tích hợp đã qua; sau các chỉnh sửa cuối, 18 test module đều qua, gồm board 200 ticket và auto-scroll. Đã xem ảnh board theo hai theme AMC và kiểm tra cửa sổ hẹp. Analyze sạch; build Windows release và Android debug thành công. AI được kiểm tra bằng HTTP local giả lập, chưa xác nhận chất lượng đầu ra với model Ollama thực tế của người dùng.

Các ticket MPS-001 đến MPS-012 trong backlog thiết kế đã hoàn tất ở phạm vi bản đầu nêu trên. Mã ticket trong tài liệu không tự tạo dữ liệu mẫu trong kho thật.

## 1. Mục tiêu và phạm vi

Tích hợp MobilePlanStudio thành module **Plan Studio** trong App Management Center (AMC). Người dùng tạo yêu cầu, làm rõ bằng AI, lưu plan, tách task và ghi note trên bảng kéo thả; mở lại ứng dụng biết ngay việc nào đang dở, bị chặn hoặc hoàn tất.

Bản đầu ưu tiên Windows desktop, lưu trên máy và gắn dữ liệu với dự án. Đồng bộ team/Firebase, giao việc cho agent và liên kết tự động với release để giai đoạn sau. Đây là lựa chọn phạm vi đề xuất, không phải yêu cầu đã được người dùng chốt.

## 2. Hiện trạng đã kiểm tra

| Thành phần | Hiện trạng | Hướng tích hợp |
|---|---|---|
| MobilePlanStudio `lib/main.dart` | Flutter; ba bước yêu cầu → làm rõ → plan; sửa, copy, xuất Markdown; state ở widget | Chuyển thành view/controller riêng trong AMC |
| MobilePlanStudio `lib/services.dart` | Ollama local tại `127.0.0.1:11434`; chọn model; câu hỏi có schema; plan 9 mục; timeout/hủy | Tách AI service có thể giả lập khi test; giữ kiểm tra dữ liệu và hủy request |
| Lưu dữ liệu Studio | UI nêu không tự lưu yêu cầu/plan; chỉ nhớ model | Bổ sung kho bản ghi và lưu nháp trước khi tích hợp AI |
| AMC | Flutter/GetX, `AppBinding`, `AppShellController`, theme và command palette | Thêm lối vào Plan Studio, tận dụng shell/theme hiện tại |
| Dự án AMC | `ReleaseProject` nhận diện bằng path; chưa có ID bền vững trong model này | Dùng registry riêng với UUID và path chuẩn hóa |
| Kho AMC | `ProjectStoreService` dùng SharedPreferences; đã có Firebase/team cho HTTP Tools | Preferences chỉ lưu tùy chọn nhỏ; ticket có repository riêng |
| Dart SDK khai báo | AMC `^3.11.4`, Studio `^3.12.2` | Kiểm tra SDK thực tế và cú pháp khi port; không chép nguyên pubspec |

Các tài liệu cũ được dùng làm thông tin tham khảo; phạm vi tài liệu này xuất phát từ yêu cầu hiện tại của người dùng.

## 3. Trải nghiệm sản phẩm

Mở **Plan Studio** từ thanh công cụ hoặc command palette. Module dùng vùng làm việc rộng, giữ project đang chọn. Hai tab chính: **Bảng công việc** và **Soạn plan**. Chuyển tab không mất nội dung đang soạn.

### Bảng công việc

- Thanh đầu: chọn dự án / tất cả dự án, tìm kiếm, lọc loại ticket, ưu tiên, nhãn, nút **Tạo ticket** và **Tạo plan bằng AI**.
- Cột trạng thái có tên, màu nhận diện, số lượng và nút tạo nhanh. Mỗi cột cuộn dọc; bảng cuộn ngang khi thiếu chiều rộng.
- Card: mã `MPS-001`, loại Plan/Task/Note, tiêu đề tối đa hai dòng, trích đoạn, ưu tiên, nhãn, ngày cập nhật; task hiện plan cha, plan hiện tiến độ task con.
- Giao diện theo theme AMC: card bo góc khoảng 14 px, khoảng cách thoáng, viền nhẹ; màu nhấn theo trạng thái. Có icon và nhãn chữ để không phụ thuộc riêng màu.
- Kéo card qua cột để đổi trạng thái; kéo trong cột để xếp thứ tự. Có bóng card đang kéo, vị trí thả dự kiến, tự cuộn ở mép và phản hồi khi lưu.
- Khi đang lọc/tìm kiếm, vẫn cho đổi trạng thái nhưng tắt sắp thứ tự trong cột để tránh thứ tự không rõ do card bị ẩn. Board tất cả dự án chỉ dùng xem/lọc; kéo thả thực hiện trong từng dự án.
- Bấm card mở panel chi tiết bên phải: nội dung, checklist, task con, note đính kèm, lịch sử và hành động đổi trạng thái. Màn hẹp mở trang chi tiết.
- Có menu **Chuyển sang…** và thao tác bàn phím thay cho kéo thả; hỗ trợ cột trống, trạng thái loading/error và board chưa có dữ liệu.

### Trạng thái và quy tắc

| Trạng thái | Ý nghĩa |
|---|---|
| Backlog — Chưa xử lý | Mới ghi nhận, chưa sẵn sàng bắt đầu |
| Ready — Sẵn sàng | Đã rõ yêu cầu và bước tiếp theo |
| In progress — Đang làm | Đang thực hiện |
| Blocked — Bị chặn | Cần ghi lý do và bước gỡ chặn |
| Review — Chờ kiểm tra | Đã làm xong phần thực hiện, cần đối chiếu tiêu chí |
| Done — Hoàn tất | Đã kiểm tra và hoàn tất |

- Tất cả loại ticket dùng cùng bộ trạng thái; Note có thể đánh Done khi đã xử lý nội dung ghi chú.
- Plan được AI tạo xong chỉ có nghĩa **nội dung đã sẵn sàng**, không tự thành Done. Lưu riêng bước soạn plan và trạng thái xử lý công việc.
- Plan có task con chỉ được Done khi mọi task con chưa lưu trữ đều Done. Hiện tiến độ `3/5 task`; note không tính vào mẫu số.
- Nếu mở lại task thuộc plan đã Done, đưa plan về In progress trong cùng giao dịch và ghi lịch sử. Nếu thêm task mới chưa hoàn tất vào plan Done, áp dụng cùng quy tắc.
- Có thể đưa ticket về trạng thái trước. Blocked bắt buộc lý do; Review/Done cần checklist bắt buộc hoàn tất nếu có.
- Archive tách riêng khỏi trạng thái; không tính ticket đã archive vào tiến độ. Hủy archive phải kiểm tra lại quy tắc plan/task. Theo yêu cầu bổ sung, đã có xóa vĩnh viễn Plan/Task/Note sau xác nhận. Xóa Plan giữ lại task con, bỏ parentId/sourceRevisionId; xóa Task cập nhật lịch sử plan cha. Nội dung bên trong ticket bị xóa cùng ticket.
- Tóm tắt: chưa xử lý = Backlog + Ready; đang xử lý = In progress + Blocked + Review; hoàn tất = Done. Hiện riêng số bị chặn.

### Soạn plan và note

1. Tạo bản ghi Plan ngay khi bắt đầu; lấy tên/path dự án làm context có thể chỉnh sửa. Đường dẫn là context, chưa có nghĩa AI đã đọc repository.
2. Lưu yêu cầu gốc, context, câu hỏi, câu trả lời và bước đang soạn. Lưu nháp sau khoảng 700 ms ngừng nhập; lưu ngay khi chuyển bước/đóng panel, có chỉ báo chưa lưu/đã lưu/lỗi.
3. AI làm rõ và tạo plan 9 mục như Studio hiện tại. Mất kết nối vẫn dùng được board, note và chỉnh nội dung thủ công.
4. Lưu plan thành revision mới; giữ bản cũ khi tạo lại. Kết quả AI gắn đúng ticket/revision nguồn, không ghi đè sửa đổi mới hoặc kết quả request đã hủy.
5. **Tạo task từ plan** mở danh sách nháp để sửa/chọn trước khi lưu. Mỗi task trỏ về plan và revision nguồn; chống tạo trùng khi bấm lại. Bản đầu cho chọn nội dung và tạo task thủ công; AI tách task là mở rộng.
6. Note có thể là card độc lập hoặc ghi chú có thời gian trong ticket. Chuyển Note thành Task giữ ID, nội dung và lịch sử.
7. Copy/xuất Markdown cho plan; xuất/nhập JSON cho backup toàn bộ board. Plan Markdown cũ được nhập thành nội dung một Plan, không suy diễn lịch sử/câu trả lời thiếu.

## 4. Mô hình dữ liệu đề xuất

| Bản ghi | Trường chính |
|---|---|
| ProjectLink | id UUID, normalizedPath, displayName; hỗ trợ gắn lại path khi di chuyển repo |
| WorkItem | id UUID, ticketNumber, projectId, type, title, body, status, priority, labels, parentPlanId, sourceRevisionId, order, checklist, blockedReason, createdAt, updatedAt, completedAt, archivedAt, revision |
| PlanDraft | workItemId, sourceRequirement, context, questions, answers, composerStep, model |
| PlanRevision | id, workItemId, version, markdown, inputSnapshot, model, createdAt |
| TicketNote | id, workItemId, body, createdAt, updatedAt |
| Activity | id, workItemId, action, previousValue, nextValue, createdAt |

ID không phụ thuộc tiêu đề/path. Chỉ Task được gắn parentPlanId tới Plan cùng dự án; không cho vòng lặp. Mã hiển thị tăng dần trong kho local, không tái sử dụng. Timestamp lưu UTC, hiển thị theo máy. Trạng thái và thứ tự là nguồn dữ liệu lưu bền, không chỉ là state giao diện.

**Lưu trữ đề xuất:** SQLite sau khi kiểm tra driver tương thích các nền tảng AMC. Repository trừu tượng để sau này thêm team backend. Chuyển cột + thứ tự + lịch sử + cập nhật plan cha thực hiện trong một transaction. Migration có schemaVersion, backup và báo lỗi rõ, không tự reset dữ liệu hỏng. Serialize lượt ghi, kiểm tra revision tránh ghi đè bản mới. Khi lưu thất bại, rollback card và báo để thử lại.

Board bản đầu là dữ liệu local trên máy, hiển thị rõ phạm vi này; đăng nhập/đổi team không tự đưa ticket lên Firebase. Bản team về sau cần namespace, phân quyền và giải quyết xung đột riêng.

## 5. Ranh giới code dự kiến

Đặt module tại `lib/app/modules/plan_studio/` gồm `models/`, `services/`, `repositories/`, `controllers/`, `views/` và `widgets/`. Các tên dưới đây là file dự kiến tạo:

- `services/ollama_plan_service.dart`: port phần Question/Ollama và prompt, tách khỏi Startup/Preferences.
- `repositories/plan_repository.dart`, `local_plan_repository.dart`: lưu bản ghi, revision, reorder, backup và migration.
- `controllers/plan_board_controller.dart`, `plan_editor_controller.dart`: tách board khỏi request AI; hủy request theo phiên soạn.
- `views/plan_studio_view.dart`, `widgets/ticket_card.dart`, `kanban_column.dart`, `ticket_detail_panel.dart`, `plan_editor.dart`.
- Tích hợp tối thiểu tại `lib/app/bindings/app_binding.dart`, `lib/app/controllers/app_shell_controller.dart`, `lib/app/views/home_view.dart` và `lib/app/views/home_widgets/command_palette.dart`.

Không thêm MaterialApp lồng nhau hoặc chuyển toàn bộ logic vào HomeController. Startup của Studio độc lập không được port sang module. Giữ timeout, model local, kiểm tra schema và chống kết quả request cũ của Studio. Không gửi nội dung sang AI release notes hoặc dịch vụ cloud ngoài luồng đã chọn.

## 6. Backlog triển khai dạng ticket

Các ticket dưới đây là bản ghi kế hoạch trong tài liệu, chưa phải dữ liệu đã được tạo trong ứng dụng. Tất cả bắt đầu **Backlog / Chưa xử lý**.

| ID | Ticket | Ưu tiên | Phụ thuộc | Điều kiện hoàn tất |
|---|---|---|---|---|
| MPS-001 | Chốt mô hình và kho lưu | P0 | — | Kiểm tra SDK/driver; model, migration, project ID và transaction có test |
| MPS-002 | Tạo/sửa/lưu trữ Plan, Task, Note | P0 | 001 | CRUD, checklist, note, chuyển loại; mở lại app còn đủ dữ liệu |
| MPS-003 | Mở module trong AMC | P0 | 002 | Toolbar/palette, project context, theme; quay lại release không mất state |
| MPS-004 | Board Kanban và card | P0 | 003 | Sáu cột, count, card, empty/loading/error, layout rộng/hẹp |
| MPS-005 | Kéo thả và lưu trạng thái | P0 | 004 | Đổi cột/thứ tự bền vững, rollback khi lỗi, menu thay thế, quy tắc parent |
| MPS-006 | Panel chi tiết và lịch sử | P0 | 005 | Ghi note, blocker, checklist, archive/restore và timeline chính xác |
| MPS-007 | Port Ollama và trình soạn | P0 | 003 | Tạo câu hỏi/plan, chọn model, hủy/retry, giữ nội dung khi AI lỗi |
| MPS-008 | Lưu nháp và revision plan | P0 | 007 | Khôi phục cả câu trả lời; tạo lại không mất bản cũ; chặn stale response |
| MPS-009 | Tách task từ plan | P1 | 006, 008 | Preview/chọn task, gắn revision, không tạo trùng, tiến độ đúng |
| MPS-010 | Tìm/lọc và tổng quan trạng thái | P1 | 006 | Lọc dự án/loại/nhãn/ưu tiên; tổng chưa làm/đang làm/xong khớp dữ liệu |
| MPS-011 | Import/export và khôi phục | P1 | 008 | Markdown, JSON có version; preview xung đột ID trước import; dữ liệu lỗi không phá kho |
| MPS-012 | Kiểm thử tích hợp và hoàn thiện UI | P0 | 009–011 | Kiểm tra lưu bền, kéo thả, AI lỗi, theme, desktop và regression AMC |

Mốc A: 001–006 → dùng được bảng ticket thủ công. Mốc B: 007–009 → hoàn chỉnh luồng yêu cầu → plan → task. Mốc C: 010–012 → tìm kiếm, backup và bản sẵn sàng dùng. Chưa ước lượng ngày công trước khi kiểm tra driver và chốt UI.

## 7. Kiểm chứng trước khi bàn giao

- Unit: serialize/migration, trạng thái, thứ tự, thống kê, quan hệ cha/con, revision, khôi phục backup và transaction rollback.
- AI service với HTTP giả lập: timeout, hủy, model không có, JSON sai/thiếu mục, output cắt ngắn và phản hồi muộn sau khi đổi ticket.
- Widget: kéo vào cột trống, reorder, bộ lọc, menu đổi trạng thái, note editor, theme sáng/tối và cửa sổ hẹp.
- Tích hợp: tạo plan → trả lời một phần → đóng/mở app → tiếp tục → tạo task → kéo trạng thái → mở lại → dữ liệu/thứ tự/tiến độ giữ nguyên.
- Mô phỏng lỗi ghi và dừng ứng dụng lúc đang lưu: không báo đã lưu trước commit, không có ticket mồ côi/lịch sử lệch; bản nháp chưa commit được hiển thị rõ.
- Chạy analyze/test phù hợp và Windows release build; smoke test mở project, release, HTTP Tools, FlowFin. Kiểm tra build Android để module desktop không gây lỗi import/khởi tạo.
- Kiểm tra board khoảng 200 ticket để phát hiện giật khi kéo, auto-scroll sai và rebuild không cần thiết.

Hoàn tất khi người dùng quản lý được Plan/Task/Note theo dự án, phân biệt việc chưa xử lý/đang làm/xong ngay trên board, và đóng/mở ứng dụng vẫn tiếp tục đúng chỗ đang dở.
