import 'package:app_management_center/app/modules/mail_cleaner/models/mail_item.dart';
import 'package:app_management_center/app/modules/mail_cleaner/models/subject_text.dart';
import 'package:app_management_center/app/modules/mail_cleaner/services/mail_imap_service.dart';
import 'package:flutter_test/flutter_test.dart';

MailItem mail(String subject, {int uid = 1, int size = 15000}) =>
    MailItem(uid: uid, subject: subject, size: size);

// Tiêu đề thật lấy từ hộp thư nganty@gtelcts.vn.
const moThat =
    '[YÊU CẦU MỞ] TÀI KHOẢN VOS DO KHÁCH HÀNG ĐÃ THANH TOÁN ĐỦ SỐ DƯ '
    'SỐ HỢP ĐỒNG 00157/2020/GFONE/VAS';
const khoaThat =
    '[YÊU CẦU KHÓA] TÀI KHOẢN VOS DO HẾT SỐ DƯ SỐ HỢP ĐỒNG 00001/2025/GIP';
const gtelVoice = '[GTEL-VOICE] THÔNG BÁO CƯỚC THÁNG 9';
const gtelThongBao =
    '[GTEL] - THÔNG BÁO TÀI KHOẢN SẮP HẾT SỐ DƯ SỐ HỢP ĐỒNG '
    '00150/2019/GFONE/VAS';

void main() {
  group('normalizeSubject', () {
    test('bỏ dấu và viết hoa', () {
      expect(normalizeSubject('[YÊU CẦU MỞ]'), '[YEU CAU MO]');
      expect(normalizeSubject('[YÊU CẦU KHÓA]'), '[YEU CAU KHOA]');
      expect(normalizeSubject('Trả lời: Đơn hàng'), 'TRA LOI: DON HANG');
    });

    test('gộp khoảng trắng thừa', () {
      expect(normalizeSubject('  A   B  '), 'A B');
    });
  });

  group('groupSignature', () {
    test('lấy nhãn trong ngoặc vuông', () {
      expect(groupSignature(moThat), '[YEU CAU MO]');
      expect(groupSignature(khoaThat), '[YEU CAU KHOA]');
      expect(groupSignature(gtelVoice), '[GTEL-VOICE]');
      expect(groupSignature(gtelThongBao), '[GTEL]');
    });

    test('thư trả lời gom chung nhóm với thư gốc', () {
      expect(groupSignature('Re: $moThat'), '[YEU CAU MO]');
      expect(groupSignature('Re: Trả lời: $khoaThat'), '[YEU CAU KHOA]');
    });

    test('không có ngoặc vuông thì lấy ba từ đầu', () {
      expect(groupSignature('THANH LÝ CHUYỂN ĐỔI HỢP ĐỒNG'), 'THANH LY CHUYEN');
    });

    test('tiêu đề rỗng vẫn có nhãn đọc được', () {
      expect(groupSignature('   '), '(không tiêu đề)');
    });
  });

  group('isReplySubject', () {
    test('nhận diện các tiền tố', () {
      expect(isReplySubject('Re: $moThat'), isTrue);
      expect(isReplySubject('Fwd: $moThat'), isTrue);
      expect(isReplySubject('Trả lời: $moThat'), isTrue);
      expect(isReplySubject(moThat), isFalse);
      expect(isReplySubject(gtelVoice), isFalse);
    });
  });

  group('SubjectRule — kiểu "bắt đầu bằng"', () {
    final rule = SubjectRule(pattern: '[YÊU CẦU MỞ]');

    test('khớp thư gốc', () {
      expect(rule.matches(mail(moThat)), isTrue);
    });

    test('khớp cả thư trả lời của đúng loại đó', () {
      expect(rule.matches(mail('Re: $moThat')), isTrue);
    });

    test('không khớp nhóm khác', () {
      expect(rule.matches(mail(khoaThat)), isFalse);
      expect(rule.matches(mail(gtelVoice)), isFalse);
      expect(rule.matches(mail(gtelThongBao)), isFalse);
    });

    test('[GTEL] không nuốt nhầm [GTEL-VOICE]', () {
      final gtel = SubjectRule(pattern: '[GTEL]');
      expect(gtel.matches(mail(gtelThongBao)), isTrue);
      expect(gtel.matches(mail(gtelVoice)), isFalse);
    });
  });

  group('SubjectRule — kiểu "có chứa"', () {
    test('tìm được cụm giữa tiêu đề, không phân biệt dấu', () {
      final rule = SubjectRule(
        pattern: 'tài khoản vos',
        kind: MatchKind.contains,
      );
      expect(rule.matches(mail(moThat)), isTrue);
      expect(rule.matches(mail(khoaThat)), isTrue);
      expect(rule.matches(mail(gtelVoice)), isFalse);
    });
  });

  group('SubjectRule — kiểu regex', () {
    test('khớp theo biểu thức', () {
      final rule = SubjectRule(
        pattern: r'^\[GTEL-\w+\]',
        kind: MatchKind.regex,
      );
      expect(rule.matches(mail(gtelVoice)), isTrue);
      expect(rule.matches(mail(gtelThongBao)), isFalse);
      expect(rule.regexError, isNull);
    });

    test('báo lỗi khi biểu thức sai cú pháp', () {
      final rule = SubjectRule(pattern: r'[unclosed', kind: MatchKind.regex);
      expect(rule.regexError, isNotNull);
      expect(rule.matches(mail(gtelVoice)), isFalse);
    });
  });

  group('copyWith', () {
    test('giữ nguồn gốc quy tắc khi đổi mẫu hoặc kiểu', () {
      final auto = SubjectRule(pattern: '[GTEL]', autoDetected: true);
      final edited = auto.copyWith(pattern: '[GTEL-VOICE]', enabled: false);
      expect(edited.pattern, '[GTEL-VOICE]');
      expect(edited.enabled, isFalse);
      expect(edited.kind, MatchKind.startsWith);
      expect(edited.autoDetected, isTrue);
    });
  });

  group('groupMail', () {
    test('sắp xếp theo dung lượng giảm dần, không theo số lượng', () {
      final items = [
        for (var i = 0; i < 100; i++) mail(moThat, uid: i, size: 15 * 1024),
        for (var i = 0; i < 10; i++)
          mail(gtelVoice, uid: 1000 + i, size: 824 * 1024),
      ];
      final groups = groupMail(items);

      // 10 thư nặng phải đứng trên 100 thư nhẹ.
      expect(groups.first.name, '[GTEL-VOICE]');
      expect(groups.first.count, 10);
      expect(groups[1].name, '[YEU CAU MO]');
      expect(groups[1].count, 100);
      expect(groups.first.totalBytes, greaterThan(groups[1].totalBytes));
    });

    test('đếm số thư trả lời trong nhóm', () {
      final groups = groupMail([
        mail(moThat, uid: 1),
        mail('Re: $moThat', uid: 2),
        mail('Re: $moThat', uid: 3),
      ]);
      expect(groups.single.count, 3);
      expect(groups.single.replyCount, 2);
      expect(groups.single.averageBytes, 15000);
    });
  });

  group('nén UID thành dải', () {
    test('gộp các UID liên tiếp', () {
      expect(MailImapService.compressRanges([1, 2, 3, 7, 8, 20]), [
        '1:3',
        '7:8',
        '20',
      ]);
    });

    test('bỏ trùng và tự sắp xếp', () {
      expect(MailImapService.compressRanges([5, 3, 4, 3]), ['3:5']);
    });

    test('danh sách rỗng', () {
      expect(MailImapService.compressRanges([]), isEmpty);
    });

    test('nén mạnh khi UID liên tục — ít lệnh IMAP hơn hẳn', () {
      final uids = List.generate(46000, (i) => i + 1);
      final ranges = MailImapService.compressRanges(uids);
      expect(ranges, ['1:46000']);
      expect(MailImapService.batchRanges(ranges).length, 1);
    });

    test('mỗi lệnh không vượt quá giới hạn ký tự', () {
      // Toàn UID lẻ => không nén được, ép sinh nhiều lệnh.
      final uids = List.generate(4000, (i) => i * 2 + 1);
      final commands = MailImapService.batchRanges(
        MailImapService.compressRanges(uids),
        limit: 2000,
      );
      expect(commands.length, greaterThan(1));
      for (final command in commands) {
        expect(command.length, lessThanOrEqualTo(2000));
      }
      // Không mất UID nào.
      final total = commands
          .map((command) => command.split(',').length)
          .reduce((a, b) => a + b);
      expect(total, uids.length);
    });
  });

  group('formatBytes', () {
    test('đổi đơn vị hợp lý', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(15 * 1024), '15 KB');
      expect(formatBytes(3 * 1048576), '3.0 MB');
      expect(formatBytes(2 * 1073741824), '2.00 GB');
    });
  });

  group('formatCount', () {
    test('phân cách hàng nghìn', () {
      expect(formatCount(48451), '48.451');
      expect(formatCount(999), '999');
      expect(formatCount(1000000), '1.000.000');
    });
  });

  group('MailboxQuota', () {
    test('tỉ lệ và ngưỡng sắp đầy', () {
      const quota = MailboxQuota(used: 9, limit: 10);
      expect(quota.ratio, 0.9);
      expect(quota.nearlyFull, isTrue);
      expect(const MailboxQuota(used: 1, limit: 0).ratio, 0);
    });
  });
}
