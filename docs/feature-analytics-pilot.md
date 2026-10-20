# Feature Analytics — pilot đầu tiên

## Đã triển khai trong code

- Dashboard **Thống kê sử dụng** ở Cài đặt và command palette, chỉ hiện khi API xác nhận quyền.
- Team admin xem team mình; quyền toàn AMC cấp riêng qua bảng `analytics_admins`.
- Bộ lọc 7/30/90 ngày UTC, team/toàn AMC và Windows/macOS/Linux; sắp xếp lượt dùng tăng/giảm.
- Người dùng hoạt động, số người đủ điều kiện, tỷ lệ dùng, lượt mở, lượt thao tác, thành công/lỗi, thiếu kết quả và quay lại ít nhất 2 ngày.
- Tracking `bundle.check`: mở trang, chọn file, kéo thả và kiểm tra lại. Kết quả chứa cảnh báo/lỗi bundle vẫn tính là kiểm tra hoàn thành; lỗi đọc file/công cụ tính riêng.
- Tính năng chưa được gắn tracking có nhãn riêng, không được diễn giải là không có ai dùng.
- Tùy chọn chia sẻ thống kê mặc định tắt. Bản debug/profile không ghi/gửi production events; không mở hoặc xóa queue production.
- SQLite outbox riêng, TTL 7 ngày, tối đa 10.000 event/10 MB payload. Flush mỗi 60 giây, tối đa 50 event/request; backoff có jitter, tuân thủ Retry-After. Chỉ xóa event đã nhận ACK.
- Khi đổi tài khoản hoặc đăng xuất: hủy upload, xóa queue cũ; đổi team giữ scope lúc phát sinh. Không lấy lỗi 401 của telemetry làm lý do logout toàn app.
- API kiểm tra danh tính, team, allowlist, kích thước, thời gian và rate limit. Retry giữ nguyên event ID; một operation chỉ có một kết quả cuối.
- Dữ liệu được lưu 90 ngày; cron mỗi giờ xóa tối đa 5.000 event quá hạn. Chưa có kho aggregate dài hạn.

## Giới hạn chủ động của pilot

Đây là lát cắt đầu tiên của [kế hoạch tổng thể](feature-analytics-plan.md), chưa phải toàn bộ MVP.
Chỉ đo thao tác AAB trên desktop; chưa đo mobile, Telegram, tác vụ tự động hay các module khác.
Chưa có chart xu hướng, p50/p95, drill-down, export CSV, build filter hoặc funnel theo visit.
Chưa có retention theo cohort hay gợi ý tự động ngừng tính năng. Khả năng mở rộng D1 chưa được load-test ở quy mô production.

Registry v1 nằm trong backend; event schema client dùng phương thức có kiểu cố định cho AAB, không nhận properties tùy ý.
Phiên bản schema là 1; lưu `build_id` qua dart-define, không gửi nội dung file hoặc lỗi nguyên văn.
Mỗi ngày có tương tác thật, client đánh dấu active/eligible cho AAB; thao tác bắt đầu cũng chứng minh eligibility nếu event ngày bị mất.
Thành công/lỗi trên dashboard được ghép với operation bắt đầu trong kỳ được chọn, tránh sai số ở ranh giới ngày.
“Chưa có kết quả” bao gồm cả đang chạy và mất terminal; chưa phân loại timeout theo loại tác vụ.

Counters dropped/rejected trong Cài đặt chỉ phản ánh tiến trình hiện tại, chưa phải báo cáo chất lượng toàn hệ thống.
Giới hạn 10 MB áp dụng cho payload còn trong queue, không phải kích thước vật lý file SQLite sau xóa.
Khi mất quyền team, các event của team đó bị server từ chối và client loại khỏi queue sau ACK.

## Chạy và phát hành

Các bước dưới đây là hướng dẫn; thay đổi code không tự triển khai backend production hoặc cấp quyền quản trị.

1. Trong `cloudflare/amc-api`, chạy `npm test` và `npm run typecheck`.
2. Kiểm tra các migration đang chờ. Workspace hiện có cả migration Safe Shares `0003` và Analytics `0004`;
   lệnh apply sẽ áp dụng mọi migration còn thiếu, cần review cùng các thay đổi hiện có trước khi phát hành.
3. Chạy migration trên môi trường đích rồi deploy Worker. Ví dụ production, sau khi đã chọn đúng account/database:

   ```powershell
   npx wrangler d1 migrations apply amc-relay --remote
   npm run deploy
   ```

4. Cấp quyền toàn AMC bằng SQL qua D1 Console, thay placeholder bằng user ID đã xác minh:

   ```sql
   INSERT OR IGNORE INTO analytics_admins(user_id)
   SELECT id FROM users WHERE id = '<verified-user-id>';
   ```

   Team admin tự có quyền xem team qua membership hiện tại, không cần thêm vào bảng trên.
   Thu hồi quyền toàn hệ thống bằng `DELETE FROM analytics_admins WHERE user_id = '<verified-user-id>';`.

5. Build desktop release với build ID ổn định:

   ```powershell
   flutter build windows --release --dart-define=AMC_BUILD_ID=analytics-pilot-20261020
   ```

   Khi chạy local Worker, dùng `AMC_API_BASE_URL=http://127.0.0.1:8787` qua dart-define hoặc env theo cơ chế backend hiện có.
   Không đổi default API URL chỉ để chạy test.

6. Trong app mới: Cài đặt → **Chia sẻ thống kê sử dụng** → bật trên tài khoản pilot.
   Kiểm tra một AAB, đợi tối đa khoảng 60 giây khi mạng ổn định; mở **Thống kê sử dụng**.
   Nếu vừa được cấp quyền, bấm **Kiểm tra quyền dashboard**.

## Kiểm chứng pilot

- Kiểm một AAB có vấn đề: 1 lượt dùng, 1 hoàn thành; không coi lỗi bundle là lỗi công cụ.
- Kiểm file không đọc được: 1 lượt dùng, 1 lỗi chuẩn hóa; server không có đường dẫn hoặc exception.
- Ngắt mạng rồi kiểm AAB, khởi động lại, nối mạng: cùng operation được tính đúng 1 lần.
- Tắt chia sẻ trước flush: queue trống, thao tác tiếp theo không được ghi.
- Đổi tài khoản giữa tác vụ: không gửi terminal của người cũ dưới người mới.
- Team admin truy vấn team khác hoặc toàn AMC: 403. Product admin được xem tổng hợp.
- Các feature chưa instrument hiển thị “Chưa gắn tracking”.

Lệnh kiểm tra local:

```powershell
flutter test test/feature_analytics_test.dart test/app_settings_service_test.dart test/app_settings_widget_test.dart test/bundle_check_widget_test.dart
```

Ảnh widget fixture để soát bố cục trên Windows (không có dữ liệu người dùng): đặt `ANALYTICS_SCREENSHOT` thành đường dẫn PNG trước khi chạy `feature_analytics_test.dart`.

## Xóa dữ liệu và rollback

Tắt chia sẻ chỉ ngừng thu thập và xóa queue chưa gửi. Muốn xóa dữ liệu đã gửi của một tài khoản,
quản trị chạy `DELETE FROM analytics_subjects WHERE user_id = '<verified-user-id>';` trong D1;
foreign key cascade xóa các event, dashboard truy vấn raw nên số liệu cập nhật ngay.
Nếu người đó bật chia sẻ và sử dụng tiếp thì dữ liệu mới được tạo lại.

Rollback client bằng bản trước hoặc tắt chia sẻ; rollback Worker bằng bản trước khi cần.
Giữ nguyên các bảng analytics khi rollback để tránh mất dữ liệu không cần thiết.
Không xóa hoặc sửa các bảng relay/QA/Safe dùng chung database.

## Đợt kế tiếp

Sau khi pilot xác nhận dữ liệu đúng: mở rộng registry và instrumentation sang Release,
Plan Studio, QA Desk và API Tools; sau đó bổ sung chart/chi tiết/export, build segmentation,
báo cáo chất lượng dữ liệu và kiểm thử tải trước khi mở rộng tới toàn bộ người dùng.
