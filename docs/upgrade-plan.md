# Kế hoạch nâng cấp — từ công cụ release thành bộ nhớ làm việc ngoài

Chốt ngày 2026-09-07. Tài liệu này ghi lại *vì sao* làm, không chỉ *làm gì* —
phần "vì sao" mới là thứ hay bị quên sau vài tuần.

## 1. Vấn đề thật

> "Tôi đang làm một việc nhưng lại bị việc khác chen ngang vào, lâu dần sinh ra
> hội chứng hay quên hoặc mất tập trung."

Cái mất khi bị chen ngang không phải thời gian, mà là **ngăn xếp trong đầu**:
đang ở bước nào, đã quyết gì, còn gì chưa kiểm. Quay lại phải dựng lại từ đầu.

Bốn nhu cầu từng liệt kê thực ra là một:

| Nhu cầu | Thực chất |
|---|---|
| Release chỉ dùng chuột | Bớt thứ phải nhớ để không quên |
| Gom doc / env / config | Bớt thứ phải đi tìm |
| Quản lý dòng tiền | Hỗ trợ bộ não đang quá tải |
| Giám sát log | Biết chuyện gì xảy ra lúc mình không nhìn |

## 2. Luận đề

**App không tồn tại để làm thay. Nó tồn tại để mình không phải nhớ.**

Đây là bộ lọc dùng để từ chối tính năng. Với mỗi đề xuất, hỏi đúng một câu:

> Thứ này làm tôi phải nhớ **thêm** hay **bớt đi**?

Thêm thì loại, dù nghe hay tới đâu. Áp dụng thẳng vào ví dụ đã bàn: một kho
tài liệu *phải bảo trì* là thêm một thứ để nhớ — nên mục "gom doc về một chỗ"
phải đổi khung thành "hiện ra đúng lúc" (xem mục 5.5).

## 3. Xương sống: runbook nối lại được

Runbook = quy trình lặp lại, có bước, chạy được, nhớ lần cuối chạy.

Giá trị thật **không phải tự động hoá** mà là **nối lại được**. Bấm chạy release,
bị chen ngang, quay lại sau 40 phút — câu hỏi duy nhất là *"tôi đang dở ở đâu?"*.
Runbook trả lời được, cái đầu thì không.

Hệ quả: **trạng thái quan trọng hơn thực thi.** Màn hình chính không mở ra bằng
danh sách việc, mà bằng *"bạn đang dở ba thứ này"*.

Runbook cũng là cách biến ghi chú thành chốt chặn. Ghi chú
`qlct-staging-deploy` viết *"`wrangler deploy` thiếu `--env` sẽ ghi đè production
bằng vars development"* chỉ bảo vệ khi nhớ mở ra đọc. Thành bước runbook, nó là
điều kiện chặn — tài liệu và hành động là cùng một vật nên không thể lệch nhau.

## 4. Phạm vi — chốt cứng

**CÓ:** tạm dừng và nối lại. Một việc chạy tại một thời điểm là chấp nhận được.

**KHÔNG:** đa luồng thật. Quyết định này cắt bỏ: tách log theo run, quản lý
tiến trình song song, UI cho nhiều thứ đang chạy, và các tình trạng tranh chấp.
Đây là phần đắt nhất của kế hoạch và nó đã bị loại có chủ đích.

Cái giá chấp nhận: trong lúc một bước **đang thực thi**, app bận.

Cửa thoát đã có sẵn trong code: `ReleaseRunnerService._runPlan` chặn theo công
thức `isRunning || (isWorkflowRunning && !allowDuringWorkflow)`. Cờ
`allowDuringWorkflow: true` cho phép chạy lệnh **giữa các bước của một workflow
đang treo** — chỉ cấm khi có lệnh đang chạy thật. Đúng thứ cần, chưa dùng đúng
mục đích.

## 5. Thứ tự thực hiện

### 5.1 Lần chạy = bản ghi bền trên đĩa

`ReleaseWorkflowRun` hiện sống trong RAM, đóng app là bốc hơi. Phải ghi ra đĩa:
đang ở bước mấy, mỗi bước xong lúc nào, output ra sao, dừng ở đâu, vì sao dừng.

Không dùng `shared_preferences` — dữ liệu quá lớn. Ghi JSON (hoặc SQLite) trong
app support dir.

**Thước đo đúng:** không phải "đóng dialog rồi mở lại", mà **tắt máy, hôm sau
bật lên, vẫn biết đang dở gì**.

### 5.2 Màn hình "bạn đang dở gì"

Mở app ra thấy cái này **trước** danh sách việc. Mỗi dòng: runbook nào, bước
nào, dừng lúc nào, lý do bắt đầu.

### 5.3 Quay lại có kiểm chứng

Đi 40 phút thì thế giới đã đổi: nhánh bị đẩy tiếp, ai đó đã deploy, token hết
hạn. **Nối thẳng vào bước tiếp theo là nguy hiểm.** Mỗi bước cần một tiền điều
kiện rẻ tiền, chạy lại lúc quay về.

Trường hợp xấu hơn — app bị kill *giữa* một bước, trạng thái không xác định.
Hai nguyên tắc lấy từ chính sản phẩm của mình:

- **Idempotency.** QLCT bắt mọi mutation mang `clientMutationId` để gửi lại vẫn
  ra kết quả cũ. Bước runbook cần đúng tính chất đó: chạy lại an toàn, hoặc tự
  nói được là đã chạy chưa.
- **App chỉ báo, người quyết định.** README QLCT: chênh lệch đối soát không tự
  thành giao dịch. Áp nguyên vào đây — **bước dở dang không được tự kết luận**.
  App đưa bằng chứng (log cuối, có artifact chưa, có exit code không), người
  quyết. Không bao giờ tự nối tiếp một bước trạng thái mù.

**Ràng buộc thiết kế:** kích thước bước quyết định chất lượng của việc quay lại.
Bước 10 phút thì nối lại gần như vô dụng. Chia bước theo *chỗ hay bị chen ngang*,
không theo *chỗ logic thấy đẹp*.

### 5.4 Release thành runbook số 1

`ReleaseWorkflowService` tổng quát hoá thành cỗ máy runbook; release trở thành
một preset, không còn là code đặc biệt.

Kiểu **xác-nhận**, không phải **quyết-định**. Gõ phím không phải cái đắt — gõ
lại được. Cái đắt là các quyết định xen giữa: version nào, ảnh Play đạt chưa,
changelog đúng chưa, deploy env nào. Nếu làm được "chỉ dùng chuột" mà vẫn bắt
quyết ngần ấy thứ thì tiết kiệm 30 giây và giữ nguyên tải nhận thức.

Đích: **app tính sẵn, đề xuất, người chỉ xác nhận hoặc bác.**

### 5.5 Doc / env / config theo ngữ cảnh

**Không làm kho.** Kho tài liệu phải bảo trì là thêm một thứ để nhớ — ngược
đúng luận đề, và là lý do mọi nỗ lực "gom về một chỗ" đều thành nghĩa địa.

Làm ngược lại: doc gắn vào repo này, runbook này, bước này — tự bật lên đúng
khoảnh khắc cần, không bao giờ phải đi duyệt tìm.

### 5.6 FlowFin

Nền đã có (client, session store, dialog). Dưới xương sống mới, FlowFin không
còn là đứa con rơi mà là **một nguồn tín hiệu** như mọi nguồn khác.

### 5.7 Log

Để cuối. Hiện `ApiMonitorService` chỉ là webview trỏ vào dashboard bên ngoài —
nền đi thuê. Xem thêm mục 7.

## 6. Tầng tín hiệu

Runbook không đến hạn theo ngày mà theo tín hiệu:

| Loại | Ví dụ | Nguồn đã có |
|---|---|---|
| Nhịp | cuối mỗi tháng | — |
| Trôi | staging 14 ngày chưa deploy | — |
| Hết hạn | keystore còn 40 ngày | Resource catalog |
| Sự kiện | PR vừa merge vào main | git |
| Ngưỡng | ngân sách đã tiêu 80% | FlowFin |
| Phiên bản | local mới hơn bản trên store | `ChPlayVersionCheckService` |
| Môi trường | fastlane sắp lỗi thời | `CiCdDependencyDoctorService` |

Phần lớn cảm biến **đã viết rồi**, chỉ đang nằm rải rác trong các panel riêng
phải chủ động mở ra xem. Việc còn lại chủ yếu là gom output và gắn nút.

**Luật chống nhiễu:** một dòng chỉ được xuất hiện nếu có hành động app làm được,
hoặc có quyết định chỉ người dùng quyết được. Thông tin thuần tuý không đủ tư
cách chiếm một dòng. Không có luật này, sau ba tháng sẽ thôi nhìn màn hình đó.

## 7. Nợ kỹ thuật chặn đường

| Vấn đề | Vị trí | Ảnh hưởng |
|---|---|---|
| `HomeController` 127KB | `lib/app/controllers/home_controller.dart` | Nếu danh sách runbook thành màn hình chính, file này phải vỡ ra trước |
| Run state chỉ trong RAM | `ReleaseWorkflowService` | Chặn thẳng mục 5.1 |
| `dashboardUrl` không được lưu | `ApiMonitorService` | Mỗi lần mở app quay về URL mặc định — một trụ cột mà chưa nhớ nổi mình muốn xem dashboard nào |
| Cờ mở dialog bị kẹt | `api_tool_dialog.dart`, `api_monitor_dialog.dart` | Đã sửa ở `flowfin_dialog.dart`; hai cái kia còn nguyên |

## 8. Bẫy đã nhận diện

- **Nghĩa địa tài liệu** — xem 5.5.
- **Xây lại Todoist.** Sẽ bị cám dỗ làm project, tag, priority, subtask,
  recurring, kéo thả sắp xếp. Khác biệt nằm ở **thực thi**, không nằm ở **sắp
  xếp**. Giữ model việc thật ngu: nguồn, nhãn, một hành động, một trạng thái.
  Không phân cấp.
- **Runbook rỗng.** Không ai dừng giữa lúc bận để viết quy trình. Tính năng cứu
  nguy: *"Bạn vừa chạy 6 lệnh trong repo này suốt 20 phút. Lưu thành runbook
  chứ?"* — `ReleaseRunnerService` đã chặn qua mọi câu lệnh nên có sẵn dữ liệu.
  Runbook viết tay thì rỗng; runbook cất từ việc đã làm thì tự đầy.
- **Ranh giới ngoài IT.** Một bước xứng đáng có mặt nếu app làm được một trong
  ba: **thực thi** nó, **kiểm chứng** nó, hoặc **mở đúng chỗ** cần mở. "Gia hạn
  domain" đạt (tra được WHOIS, mở đúng trang, ghi hạn mới). "Đi khám sức khoẻ"
  trượt — đừng nhét vào.

## 9. Đã xong trên nhánh `feature/flowfin-module-rebrand`

- Rebrand App Release Center → App Management Center, kèm
  `LegacyStorageMigrationService` cứu dữ liệu đã lưu khi `ProductName` đổi làm
  `getApplicationSupportDirectory()` trỏ sang thư mục khác.
- Module FlowFin: `FlowFinApiClient` gọi thẳng FlowFin Worker, không đụng
  Firebase hay relay của app này. Session tách theo môi trường trong secure
  store. Dialog có đăng nhập + overview.

## 10. Câu chưa trả lời

- **Tên sản phẩm.** "App Management Center" là tên mô tả, mà app này không có
  một mô tả nào bao hết được — nên nó sẽ chật lần nữa. Cần tên định danh, không
  phải tên mô tả. Chốt trước khi phát hành bản cài đầu tiên: đổi lúc này gần như
  miễn phí, sau đó thì phải trả giá migration lần nữa.
- **Neo định danh.** Nên đóng băng vĩnh viễn những thứ máy dùng để nhận diện
  app (package Dart, `ProductName` trong `Runner.rc`, `applicationId`, Firebase
  project id) và chỉ đổi phần người nhìn thấy. Làm vậy thì rebrand lần sau chỉ
  là sửa vài chuỗi hiển thị.
- **Runbook thứ hai là gì?** Cái thứ nhất là release. Cái thứ hai tiết lộ đây là
  dev tool hay thật sự là công cụ "không chỉ IT".
