# TURN cho SwiftDesk AMC

`turnserver.conf.example` là cấu hình mẫu, chưa được triển khai hay kiểm chứng
với coturn trong đợt này. Cần máy chủ IP public, hostname/TLS cert và secret riêng.
Thay toàn bộ placeholder trước khi chạy; giữ cấu hình có secret ngoài Git.

API AMC cấp username/password tạm theo chuẩn TURN REST của coturn, tối đa
15 phút/phiên. Chỉ API và coturn giữ shared secret; không đưa secret vào app,
frontend, invitation hay `--dart-define`.

- API: `TURN_URLS`, `STUN_URLS`, secret `TURN_SECRET`.
- Coturn: `static-auth-secret` trùng `TURN_SECRET`, hostname/realm đúng máy chủ.
- Network: 3478 UDP/TCP; 443 TCP cho TURN TLS; relay UDP 49160–49200.
- NAT: khai báo external IP/mapping nếu máy TURN đứng sau NAT; tránh dùng proxy
  HTTP/Cloudflare orange-cloud trước TURN.
- Hạn chế peer IP nội bộ/metadata và quota trong mẫu; điều chỉnh băng thông/quota
  theo tải đã đo, không mở relay không xác thực để thử.

Kiểm chứng staging bắt buộc: hai mạng khác nhau, force relay, chặn UDP/TLS443,
stats candidate pair = relay, ticket hết hạn/dùng lại bị từ chối, revoke đóng
phiên, clipboard/input đúng scope và không kẹt phím khi mất mạng.

Xem [hướng dẫn Phase 3/4](../../docs/swiftdesk-phase34.md) và
[cấu hình coturn chính thức](https://github.com/coturn/coturn/blob/master/examples/etc/turnserver.conf).
