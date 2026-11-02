# Feature Analytics — phase 2

Ngày 20/10/2026. Đã mở rộng tracking trong code từ pilot AAB sang Release,
Plan Studio, QA Desk và API Tools. Chưa triển khai Worker hoặc phát hành client production.
Thiết lập quyền, consent, queue và retention kế thừa [pilot](feature-analytics-pilot.md).

## Phạm vi đo

| Feature ID | Một lượt dùng | Kết quả hoàn thành |
|---|---|---|
| `bundle.check` | Kiểm tra một AAB | Có báo cáo, kể cả phát hiện vấn đề |
| `release.android` | Bắt đầu workflow hoặc chủ động retry bước lỗi | Workflow kết thúc thành công hoặc có cảnh báo xác minh |
| `release.ios.build` | Gọi build IPA tại Mac | Build hoàn tất |
| `release.ios.upload` | Gọi upload IPA tại Mac | Gửi upload xong; không đồng nghĩa đã lên TestFlight/App Store |
| `plan.create` | Tạo ticket từ menu hoặc quick-add | Ghi ticket thành công |
| `plan.bulk_create` | Tạo nhiều ticket từ dialog hoặc task con từ editor | Ghi cả batch thành công |
| `plan.ai_generate` | Tạo hoặc tạo lại nội dung plan bằng AI | Nhận và lưu kết quả thành công |
| `qa.run` | Chạy một batch suite đã chọn, kể cả chạy lại | Có kết quả; test fail vẫn là công cụ chạy hoàn tất |
| `api.send` | Gửi request trực tiếp trong API Tools | Nhận HTTP response, kể cả 4xx/5xx |

Các feature iOS chỉ đủ điều kiện trên macOS. Các feature còn lại đo desktop.
Eligibility được ghi khi tài khoản bật chia sẻ có tương tác chủ động; thiếu công cụ
hoặc cấu hình không loại người đó khỏi mẫu số. Client pilot chỉ đóng góp eligibility AAB.

Một batch 100 ticket hoặc nhiều suite QA là **một lượt dùng**, không phải 100 lượt.
Retry do người dùng là lượt mới; retry gửi telemetry giữ nguyên ID.
Autosave, tải model AI, polling, API Monitor và remote release không sinh lượt dùng trực tiếp.
Remote được loại trừ để không gán hoạt động của người điều khiển cho tài khoản máy host.
Thao tác legacy chạy script rời không nằm trong `release.android`.

Lượt mở đo ở trang/dialog chính: AAB, Android Release, iOS Release, Plan Studio,
QA Desk, API Tools. Lượt mở Plan Studio gắn với `plan.create`, iOS Release gắn
với `release.ios.build`; chưa có lượt mở riêng cho bulk, AI hoặc upload.
Không suy ra funnel cho các tính năng con từ các số lượt mở này.

## Kết quả và dashboard

- Dashboard có thêm cột **Đã hủy** và **Chờ kết quả / xác minh**.
- Hủy không được tính là lỗi hoặc thành công. Kết quả AI đến sau khi hủy không sinh kết quả thứ hai.
- QA không khởi chạy được công cụ tính là lỗi; suite chạy xong báo test fail có kết quả `issues_found`.
- Mất kết nối upload iOS khi chưa biết Apple đã nhận hay chưa có kết quả
  `verification_required`; backend xếp vào chờ xác minh, kể cả service ném exception.
- `submitted` chỉ xác nhận thao tác gửi upload. Polling trạng thái Apple không tạo lượt mới.
- Phase này chưa cập nhật ngược kết quả analytics sau khi một upload mơ hồ được xác minh;
  thao tác đó vẫn ở nhóm chờ xác minh trong báo cáo.
- Lọc Windows/Linux hiển thị iOS **Không áp dụng**, không phải 0 người dùng.
- Safe, Mail Cleaner, FlowFin và Remote vẫn có nhãn **Chưa gắn tracking**.

Client không gửi nội dung ticket, prompt, URL/header/body API, đường dẫn, log QA,
tên dự án, private key hoặc exception nguyên văn. Chỉ gửi các enum cố định và metadata
trong allowlist. Không thêm SDK hoặc dịch vụ bên ngoài.

## Tương thích và phát hành

Client mới gửi schema **2**. Worker mới chấp nhận cả schema **1** của pilot và schema **2**.
Không cần migration mới ngoài `0004_feature_analytics.sql` đã có.

**Triển khai Worker mới trước khi phân phối client mới.** Worker pilot sẽ từ chối
event schema 2 và client sẽ loại event đã bị từ chối khỏi queue sau ACK.
Không rollback Worker về bản pilot trong khi vẫn còn client schema 2 đang gửi dữ liệu.

Nếu môi trường chưa chạy pilot, làm các bước migration/quyền trong
[hướng dẫn pilot](feature-analytics-pilot.md), kiểm tra cả migration đang chờ của module khác.
Sau đó build:

```powershell
flutter build windows --release --dart-define=AMC_BUILD_ID=analytics-phase2-20261020
```

Trong app, bật **Cài đặt → Chia sẻ thống kê sử dụng**, thực hiện thao tác rồi đợi
đồng bộ. Team admin xem team của mình; product admin được cấp riêng quyền toàn AMC.
Debug/profile vẫn không ghi hoặc gửi dữ liệu production.

## Kiểm chứng

- Backend: schema 1/2, feature/platform/result allowlist, quyền team/toàn AMC,
  dedup, terminal xung đột, cancellation và upload chờ xác minh.
- Client: offline/đổi tài khoản/consent; tạo một ticket và batch 100 ticket;
  autosave không đếm; AI hủy với response hoặc exception muộn;
  API background không đếm, HTTP 500/network error/cancel tách riêng.
- Workflow: Android retry/cancel/preflight/remote; iOS build/upload và polling;
  QA nhiều suite vẫn một batch, hủy batch được ghi riêng.
- Widget: dashboard phân biệt chưa đo/không áp dụng, bộ lọc và đổi tài khoản;
  Plan Studio và các dialog release/API giữ hành vi hiện có.
- iOS được kiểm tra bằng runner giả trên Windows; vẫn cần smoke test trên Mac
  trước khi phân phối bản macOS.

## Đợt tiếp theo

Chart xu hướng theo ngày, chi tiết tính năng, export CSV, lọc build, chất lượng dữ liệu
và kiểm thử tải D1. Chưa làm các phần này trong phase 2. Số liệu chỉ đại diện tài khoản
bật chia sẻ trên client có hỗ trợ; chưa có inventory để xác định độ phủ toàn bộ cài đặt.
