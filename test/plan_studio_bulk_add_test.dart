import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_management_center/app/modules/plan_studio/models/work_item.dart';
import 'package:app_management_center/app/modules/plan_studio/repositories/local_plan_repository.dart';
import 'package:app_management_center/app/modules/plan_studio/services/bulk_add_parser.dart';
import 'package:app_management_center/app/modules/plan_studio/services/deadline.dart';
import 'package:app_management_center/app/modules/plan_studio/widgets/bulk_create_dialog.dart';
import 'package:app_management_center/app/modules/plan_studio/widgets/quick_add_field.dart';

void main() {
  // Tuesday 29/09/2026.
  final now = DateTime(2026, 9, 29, 10);
  const pasted =
      '## Sprint 12\n'
      '- Thiết kế màn đăng nhập !p1 #mobile\n'
      '* [ ] Viết API xác thực ^t6\n'
      '3. Kiểm thử iOS ^25/10 17h\n'
      '\n'
      '   + [x] Cập nhật tài liệu\n'
      '!p2 #only\n';
  // A status report pasted as-is.
  const report =
      '➡️ 🔴 Cao – Kiểm tra lại luồng đăng nhập VNeID: link callback đã bị đổi, '
      'cần Smart City hoặc các bên liên quan cấu hình lại đúng link callback '
      'https://vneid.fizahub.vn/callback\n'
      '➡️ 🔴 Cao – Sửa lỗi phát tiếng chụp ảnh khi chụp mặt sau CCCD trên iOS\n'
      '➡️ 🔴 Cao – Tích hợp miniapp FizaHUB vào Smart City Đà Nẵng\n'
      '➡️ 🔴 Cao – Tích hợp tính năng hóa đơn điện tử (HĐĐT) với HILO vào FizaHUB\n'
      '➡️ 🟡 Trung bình – Tích hợp truy xuất nguồn gốc (TXNG) VNeCheck vào '
      'FizaHUB: kích hoạt tem, tạo lô truy xuất\n'
      '➡️ 🟡 Trung bình – Tích hợp miniapp thương mại điện tử Numbala và VNetrip '
      'vào FizaHUB\n'
      '➡️ ⏳ Chờ phản hồi – Chờ IVAN báo lại kết quả nghiệm thu luồng BHXH\n';

  group('parseBulkAdd', () {
    test('one task per line, list markers and headings dropped', () {
      final lines = parseBulkAdd(pasted, now);
      expect(lines.map((l) => l.parsed.title), [
        'Thiết kế màn đăng nhập',
        'Viết API xác thực',
        'Kiểm thử iOS',
        'Cập nhật tài liệu',
      ]);
      expect(lines[0].parsed.priority, 'P1');
      expect(lines[0].parsed.labels, ['mobile']);
      expect(lines[1].parsed.due, DateTime(2026, 10, 2));
      expect(lines[2].parsed.due, DateTime(2026, 10, 25, 17));
      expect(lines[2].parsed.allDay, isFalse);
      expect(lines.any((l) => l.duplicate), isFalse);
    });

    test('highlights point at each line\'s tokens in the whole text', () {
      final input = BulkAddController(text: pasted)..clock = () => now;
      expect(input.highlights.map((t) => t.range.textInside(pasted)), [
        '!p1',
        '#mobile',
        '^t6',
        '^25/10 17h',
      ]);
      input.dispose();
    });

    test('repeated titles are marked, ignoring case and tokens', () {
      final lines = parseBulkAdd(
        'Viết test\nviết test #qa\nViết test khác',
        now,
      );
      expect(lines.map((l) => l.duplicate), [false, true, false]);
    });

    test('numbers in a title and Windows line endings are kept apart', () {
      final lines = parseBulkAdd(
        '2 màn hình cần sửa\r\n1.5 giờ ước lượng\r\n',
        now,
      );
      expect(lines.map((l) => l.parsed.title), [
        '2 màn hình cần sửa',
        '1.5 giờ ước lượng',
      ]);
    });
  });

  group('report-style priority', () {
    test('a pasted status report keeps titles, priorities and waiting', () {
      final lines = parseBulkAdd(report, now);
      expect(lines, hasLength(7));
      expect(
        lines.first.parsed.title,
        'Kiểm tra lại luồng đăng nhập VNeID: link callback đã bị đổi, cần '
        'Smart City hoặc các bên liên quan cấu hình lại đúng link callback '
        'https://vneid.fizahub.vn/callback',
      );
      expect(
        lines[4].parsed.title,
        'Tích hợp truy xuất nguồn gốc (TXNG) VNeCheck vào FizaHUB: kích hoạt '
        'tem, tạo lô truy xuất',
      );
      expect(lines.map((l) => l.parsed.priority), [
        'P1',
        'P1',
        'P1',
        'P1',
        'P2',
        'P2',
        null,
      ]);
      expect(lines.map((l) => l.waiting), [
        false,
        false,
        false,
        false,
        false,
        false,
        true,
      ]);
      expect(
        lines.last.parsed.title,
        'Chờ IVAN báo lại kết quả nghiệm thu luồng BHXH',
      );
    });

    test('words, dots, bold and plain text all resolve', () {
      String? level(String line) =>
          parseBulkAdd(line, now).single.parsed.priority;
      expect(level('Khẩn cấp – Sửa crash'), 'P0');
      expect(level('Gấp: Sửa crash'), 'P0');
      expect(level('➡️ 🔴 **Cao** – Sửa crash'), 'P1');
      expect(level('Trung binh - Viet API'), 'P2');
      expect(level('Bình thường: Viết API'), 'P2');
      expect(level('🟢 Thấp — Dọn code'), 'P3');
      expect(level('🟡 Viết tài liệu'), 'P2');
      // The word outranks the dot; an inline token outranks both.
      expect(level('🔴 Thấp – Dọn code'), 'P3');
      expect(level('🟢 Thấp – Sửa lỗi !p0'), 'P0');
      expect(parseBulkAdd('⏳ Đối tác ký hợp đồng', now).single.waiting, isTrue);
    });

    test('a word without a dash or colon is part of the title', () {
      final line = parseBulkAdd('Cao tốc Đà Nẵng mở rộng', now).single;
      expect(line.parsed.title, 'Cao tốc Đà Nẵng mở rộng');
      expect(line.parsed.priority, isNull);
    });

    test('the prefix is highlighted with the priority it resolved to', () {
      const text = 'Viết API\n➡️ 🔴 Cao – Sửa lỗi #ios';
      final input = BulkAddController(text: text)..clock = () => now;
      expect(input.highlights.map((t) => t.range.textInside(text)), [
        '🔴 Cao –',
        '#ios',
      ]);
      expect(input.highlights.first.priority, 'P1');
      input.dispose();
    });
  });

  group('bulkDrafts', () {
    final plan = WorkItem(
      id: 'plan',
      projectId: 'project',
      title: 'Plan',
      type: WorkType.plan,
    );
    setDue(plan, DateTime(2026, 10, 10));

    test('skips repeats and applies column, plan and defaults', () {
      final drafts = bulkDrafts(
        parseBulkAdd('A !p0 #ui\nB\na', now),
        projectId: 'project',
        status: WorkStatus.ready,
        plan: plan,
      );
      expect(drafts.map((d) => d.title), ['A', 'B']);
      expect(drafts.map((d) => d.priority), ['P0', 'P2']);
      expect(drafts.first.labels, ['ui']);
      expect(drafts.every((d) => d.status == WorkStatus.ready), isTrue);
      expect(drafts.every((d) => d.parentId == 'plan'), isTrue);
      expect(drafts.every((d) => d.dueAt == null), isTrue);
      expect(drafts.map((d) => d.id).toSet(), hasLength(2));
    });

    test('a waiting line goes to the blocked column with its reason', () {
      final drafts = bulkDrafts(
        parseBulkAdd(report, now),
        projectId: 'project',
        status: WorkStatus.ready,
      );
      expect(drafts.where((d) => d.status == WorkStatus.ready), hasLength(6));
      expect(drafts.last.status, WorkStatus.blocked);
      expect(drafts.last.blockedReason, bulkWaitingReason);
      expect(drafts.last.priority, 'P2');
      expect(drafts.first.blockedReason, isEmpty);
    });

    test('a line\'s own deadline wins over the inherited plan deadline', () {
      final drafts = bulkDrafts(
        parseBulkAdd('A ^mai\nB', now),
        projectId: 'project',
        status: WorkStatus.backlog,
        plan: plan,
        inheritDue: true,
      );
      expect(drafts[0].dueAt!.toLocal().day, 30);
      expect(drafts[1].dueAtUtc, plan.dueAtUtc);
      expect(drafts[1].dueAllDay, isTrue);
    });
  });

  group('createMany', () {
    late Directory directory;
    late LocalPlanRepository repository;
    late StudioProject project;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('plan-studio-bulk-');
      repository = await LocalPlanRepository.open(
        path: '${directory.path}/studio.sqlite',
      );
      project = await repository.ensureProject('${directory.path}/project');
    });
    tearDown(() async {
      await repository.close();
      await directory.delete(recursive: true);
    });
    WorkItem draft(
      String title, {
      WorkStatus status = WorkStatus.backlog,
      String? parent,
      String? projectId,
    }) => WorkItem(
      id: 'id-$title',
      projectId: projectId ?? project.id,
      title: title,
      status: status,
      parentId: parent,
    );

    test(
      'numbers in order, appends to each column, reopens a done plan',
      () async {
        final first = await repository.save(draft('Có sẵn'));
        final plan = await repository.save(
          draft('Plan', status: WorkStatus.done)..type = WorkType.plan,
        );
        final created = await repository.createMany([
          draft('A', parent: plan.id),
          draft('B', parent: plan.id),
          draft('C', status: WorkStatus.ready),
        ]);
        expect(created.map((i) => i.number), [3, 4, 5]);
        expect(created.map((i) => i.order), [1, 2, 0]);
        expect(created.every((i) => i.revision == 1), isTrue);
        expect(created.first.activity.last['text'], 'Tạo task hàng loạt');
        final all = await repository.items();
        expect(all, hasLength(5));
        expect(
          all.firstWhere((i) => i.id == first.id).revision,
          first.revision,
        );
        final reopened = all.firstWhere((i) => i.id == plan.id);
        expect(reopened.status, WorkStatus.inProgress);
        expect(reopened.activity.last['text'], 'Thêm 2 task con');
      },
    );

    test(
      'a pasted report is stored with priorities and a blocked task',
      () async {
        final created = await repository.createMany(
          bulkDrafts(
            parseBulkAdd(report, now),
            projectId: project.id,
            status: WorkStatus.backlog,
          ),
        );
        expect(created, hasLength(7));
        final blocked = created.where((i) => i.status == WorkStatus.blocked);
        expect(blocked.single.blockedReason, bulkWaitingReason);
        expect(blocked.single.order, 0);
        expect(created.where((i) => i.priority == 'P1'), hasLength(4));
      },
    );

    test('one invalid draft rolls the whole batch back', () async {
      await expectLater(
        repository.createMany([draft('A'), draft('B', parent: 'missing-plan')]),
        throwsStateError,
      );
      await expectLater(
        repository.createMany([draft('A', projectId: 'missing')]),
        throwsStateError,
      );
      expect(await repository.items(), isEmpty);
      final next = await repository.createMany([draft('A')]);
      expect(next.single.number, 1);
    });

    test('rejects an archived plan and an existing ticket', () async {
      final plan = await repository.save(
        draft('Plan')
          ..type = WorkType.plan
          ..archived = true,
      );
      await expectLater(
        repository.createMany([draft('A', parent: plan.id)]),
        throwsStateError,
      );
      final saved = await repository.save(draft('B'));
      await expectLater(
        repository.createMany([
          WorkItem.fromJson(saved.toJson())..revision = 0,
        ]),
        throwsStateError,
      );
      expect(await repository.items(), hasLength(2));
    });
  });
}
