import 'package:flutter/material.dart';

import '../theme/qa_tokens.dart';
import '../widgets/qa_widgets.dart';

/// A short guide to where things are; the empty states carry the first steps.
Future<void> showQaHelp(BuildContext context) => showQaSideSheet<void>(
  context,
  key: const Key('qa-help-sheet'),
  title: 'Hướng dẫn QA Desk',
  subtitle: 'Chạy test của nhiều dự án, rồi biến lỗi thành task',
  width: 520,
  builder: (_) => const _HelpBody(),
);

class _HelpBody extends StatelessWidget {
  const _HelpBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    Widget section(IconData icon, String title, List<String> lines) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tokens.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      line,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        section(Icons.play_circle_outline, 'Chạy test', [
          'Tick suite trên cây; tick nguồn là chọn cả nguồn. Môi trường chọn '
              'ngay trên dòng nguồn, 🔑 cho biết đã nhập đủ secret chưa.',
          'Chip Thiết bị, Mạng, Appium phía trên lượt chạy mở bảng chỉnh tương '
              'ứng. Thanh dưới cùng tóm tắt lựa chọn và nói rõ vì sao chưa chạy '
              'được.',
          'Nguồn chạy song song, suite trong một nguồn chạy lần lượt; suite '
              'mobile xếp hàng chung để không tranh một thiết bị. Đóng trang '
              'không dừng lượt chạy.',
        ]),
        section(Icons.assignment_outlined, 'Kết quả và báo cáo issue', [
          'Xong mỗi lượt có thẻ kết quả. Báo cáo issue gom mỗi suite lỗi thành '
              'một task gợi ý, kèm cách tái hiện, lệnh, môi trường, Git và trích '
              'log; Copy task hoặc Copy báo cáo để dán vào công cụ quản lý task.',
          'Diễn giải dựa trên log, không khẳng định nguyên nhân gốc. Không có '
              'lỗi chỉ nghĩa là các suite đã chạy đều qua.',
          'Kết quả giữ mọi lượt: chi tiết từng suite, so sánh với lượt trước, '
              'xu hướng, chạy lại suite lỗi, xuất HTML, JUnit XML (kèm log) hoặc '
              'JSON.',
        ]),
        section(Icons.account_tree_outlined, 'Kịch bản và môi trường', [
          'Test case mô tả điều kiện, các bước, kết quả mong đợi và gắn với một '
              'suite để chạy lại. Lưu ở .fiza-qa/scenarios.json trong dự án.',
          'Môi trường là các biến truyền vào tiến trình suite. Secret chỉ lưu '
              'tên; giá trị nhập theo phiên và không ghi xuống đĩa.',
        ]),
        section(Icons.smart_toy_outlined, 'QA Desk tự thao tác app', [
          'Test case "QA Desk tự thao tác" là các bước (mở app, đăng nhập, bấm, '
              'nhập, thấy…) QA Desk chạy bằng Maestro trên máy ảo, điện thoại '
              'hoặc trình duyệt; không cần viết code test trong dự án.',
          'Đăng nhập bằng tài khoản demo trong kho (nút Tài khoản demo trên thanh '
              'tiêu đề). '
              'Kho của team được mã hoá bằng passphrase; server chỉ giữ bản '
              'mã. Mật khẩu vào app qua biến \${MAESTRO_QA_PASSWORD}, không '
              'nằm trong flow hay log.',
          'Kịch bản ghi dữ liệu không bao giờ chạy trên production; tài khoản '
              'production luôn chỉ đọc. Chạy trên production phải xác nhận.',
          'Khai app trong .fiza-qa/project.yaml như mẫu dưới, kèm flow đăng '
              'nhập (flows/login.yaml) dùng \${MAESTRO_QA_USERNAME} và '
              '\${MAESTRO_QA_PASSWORD}.',
        ]),
        Container(
          margin: const EdgeInsets.fromLTRB(32, 0, 0, 18),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: tokens.well,
            borderRadius: BorderRadius.circular(QaTokens.radius),
            border: Border.all(color: tokens.line),
          ),
          child: SelectableText(_appsSample, style: tokens.mono(size: 11.5)),
        ),
        section(Icons.circle_outlined, 'Đọc trạng thái', [
          'Qua: lệnh kết thúc với exit code 0. Lỗi: cần xem log, có thể do ứng '
              'dụng hoặc môi trường. Đã dừng: chưa có kết luận, cần chạy lại.',
        ]),
        section(Icons.description_outlined, 'Suite đến từ đâu', [
          'Mỗi dự án có thể tự khai suite ở .fiza-qa/project.yaml; không có '
              'file đó thì QA Desk đoán suite an toàn theo loại dự án.',
          'Chỉ chạy được flutter, dart, node, npm, npx, adb và appium. Suite '
              'mobile khai requiresDevice, requiresPhysicalDevice hoặc '
              'requiresAppium, và dùng {deviceId}, {deviceName}, {appiumPort} '
              'trong tham số.',
        ]),
        section(Icons.folder_outlined, 'Dữ liệu nằm ở đâu', [
          'Danh sách nguồn, lịch sử và log nằm trong thư mục qa_desk của AMC '
              '(%APPDATA%\\com.example\\App Management Center\\qa_desk).',
        ]),
      ],
    );
  }
}

const _appsSample = '''apps:
  - id: shop
    name: Shop
    platform: android        # hoặc web (dùng url thay appId)
    login: flows/login.yaml
    cleanup: flows/cleanup.yaml
    productionGuard: [Xoá, Thanh toán]
    environments:
      staging:
        appId: vn.example.shop.staging
        build: build/app/outputs/flutter-apk/app-staging-release.apk
      production:
        appId: vn.example.shop
        production: true''';
