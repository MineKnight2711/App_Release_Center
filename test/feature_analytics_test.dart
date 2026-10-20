import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_management_center/app/models/auth_models.dart';
import 'package:app_management_center/app/modules/analytics/analytics_outbox.dart';
import 'package:app_management_center/app/modules/analytics/analytics_transport.dart';
import 'package:app_management_center/app/modules/analytics/analytics_view.dart';
import 'package:app_management_center/app/modules/analytics/feature_analytics_service.dart';
import 'package:app_management_center/app/services/app_settings_service.dart';
import 'package:app_management_center/app/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_management_center/app/modules/bundle_check/controllers/bundle_check_controller.dart';
import 'package:app_management_center/app/modules/bundle_check/models/bundle_check_models.dart';
import 'package:app_management_center/app/modules/bundle_check/services/bundle_check_service.dart';
import 'package:app_management_center/app/modules/bundle_check/services/bundle_check_store.dart';
import 'package:app_management_center/app/modules/bundle_check/services/android_toolchain.dart';

class _NoProjects implements BundleProjectSource {
  @override
  Future<List<BundleProjectCandidate>> candidates() async => [];
  @override
  Future<KeystoreRef?> savedKeystore(BundleProjectCandidate candidate) async =>
      null;
}

class _BundleFixtureService extends BundleCheckService {
  _BundleFixtureService(Directory directory)
    : super(
        store: BundleCheckStore(root: directory),
        projects: _NoProjects(),
      );
  bool failRead = false;
  @override
  Future<BundleCheckRun> check(
    String path, {
    BundleProjectCandidate? project,
    bool detachProject = false,
    bool runBundletoolValidate = true,
    void Function(String)? onProgress,
  }) async {
    if (failRead) throw FileSystemException('private file error', path);
    return BundleCheckRun(
      report: BundleCheckReport.fromJson({
        'sourcePath': path,
        'results': [
          {'id': 'signing', 'status': 'fail', 'title': 'Private report'},
        ],
      }),
      candidates: [],
      contract: const EnvContract(),
    );
  }
}

class _SessionStore implements AuthSessionStore {
  @override
  AuthSessionMetadata? authSession;
  @override
  Future<void> clearAuthSession() async => authSession = null;
  @override
  Future<void> saveAuthSession(AuthSessionMetadata value) async =>
      authSession = value;
}

CurrentUserProfile profile(String uid, {String team = 'team-a'}) =>
    CurrentUserProfile(
      uid: uid,
      email: 'never-sent@example.com',
      displayName: 'Never sent',
      teamId: team,
      teamName: 'Private team',
      role: TeamRole.admin,
      sessionExpiresAt: DateTime.now().add(const Duration(days: 1)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppSettingsService settings;
  late AuthService auth;
  late DateTime now;
  late AnalyticsOutbox box;
  late FeatureAnalyticsService service;
  late FutureOr<http.Response> Function(http.Request) respond;
  late List<Map<String, dynamic>> batches;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      AppSettingsService.analyticsEnabledKey: true,
    });
    settings = await AppSettingsService().init();
    auth = AuthService(sessionStore: _SessionStore());
    auth.profile.value = profile('user-a');
    auth.authStatus.value = AuthStatus.authenticated;
    now = DateTime.utc(2026, 10, 20, 12);
    temp = await Directory.systemTemp.createTemp('amc_analytics_test_');
    box = await AnalyticsOutbox.open(path: '${temp.path}/events.sqlite');
    batches = [];
    respond = (request) {
      if (request.url.path.endsWith('/access')) {
        return http.Response(
          jsonEncode({
            'global': false,
            'teams': [
              {'id': 'team-a', 'name': 'Team A'},
            ],
          }),
          200,
        );
      }
      final batch = jsonDecode(request.body) as Map<String, dynamic>;
      batches.add(batch);
      return http.Response(
        jsonEncode({
          'ack': [
            for (final event in batch['events'])
              {'event_id': event['event_id'], 'status': 'accepted'},
          ],
        }),
        200,
      );
    };
    service = FeatureAnalyticsService(
      settings: settings,
      auth: auth,
      transport: AnalyticsTransport(
        baseUrl: Uri.parse('https://amc.test'),
        readToken: () async => 'token',
        clientFactory: () => MockClient((r) async => await respond(r)),
      ),
      openOutbox: () async => box,
      now: () => now,
      production: true,
      buildId: 'test-build',
      platform: 'windows',
    );
  });
  tearDown(() async {
    await service.shutdown();
    await box.close();
    await temp.delete(recursive: true);
  });

  test(
    'events survive network failure and retry with identical IDs and no content',
    () async {
      service.start();
      await service.settled;
      service.opened();
      final operation = service.begin(AnalyticsSource.drop);
      service.complete(operation, issuesFound: true);
      service.fail(
        operation,
        AnalyticsFailure.unexpected,
      ); // second result ignored
      await service.settled;
      final before = await box.batch('user-a', now);
      expect(before.map((e) => e['event_name']), [
        'app.active_day',
        'feature.eligible_day',
        'feature.opened',
        'action.started',
        'action.completed',
      ]);
      final success = respond;
      respond = (r) => r.url.path.endsWith('/events')
          ? throw const SocketException('offline')
          : success(r);
      await service.flush();
      expect(await box.batch('user-a', now), before);
      respond = success;
      now = now.add(const Duration(hours: 2));
      await service.flush();
      expect(batches.single['events'], before);
      expect(await box.batch('user-a', now), isEmpty);
      expect(jsonEncode(batches), isNot(contains('never-sent')));
      expect(batches.single['events'].last['result_category'], 'issues_found');
    },
  );

  test(
    'opt-out purges pending data and stops an in-flight operation from recording',
    () async {
      service.start();
      final operation = service.begin(AnalyticsSource.filePicker);
      await service.settled;
      await settings.setAnalyticsEnabled(false);
      service.complete(operation, issuesFound: false);
      await service.settled;
      await service.flush();
      expect(await box.batch('user-a', now), isEmpty);
      expect(batches, isEmpty);
      expect(
        (await AppSettingsService().init()).analyticsEnabled.value,
        isFalse,
      );
    },
  );

  test(
    'switching account clears the old queue and never sends it as the new user',
    () async {
      service.start();
      final operation = service.begin(AnalyticsSource.filePicker);
      await service.settled;
      auth.profile.value = profile('user-b', team: 'team-b');
      service.complete(operation, issuesFound: false);
      service.opened();
      await service.settled;
      expect(await box.batch('user-a', now), isEmpty);
      await service.flush();
      expect(batches.single['expected_user_id'], 'user-b');
      expect(
        (batches.single['events'] as List).every(
          (e) => e['team_id'] == 'team-b',
        ),
        isTrue,
      );
      expect(
        (batches.single['events'] as List).any(
          (e) => e['operation_id'] == operation!.id,
        ),
        isFalse,
      );
    },
  );

  test(
    '401 pauses uploader without logging out the app; ACK drops only named events',
    () async {
      service.start();
      service.opened();
      await service.settled;
      final success = respond;
      respond = (r) => r.url.path.endsWith('/events')
          ? http.Response('{}', 401)
          : success(r);
      await service.flush();
      expect(auth.profile.value!.uid, 'user-a');
      expect(await box.batch('user-a', now), hasLength(3));
      auth.profile.value = profile('user-a'); // reauthentication resumes
      respond = (r) {
        if (!r.url.path.endsWith('/events')) return success(r);
        final events = (jsonDecode(r.body) as Map)['events'] as List;
        return http.Response(
          jsonEncode({
            'ack': [
              {'event_id': events[0]['event_id'], 'status': 'duplicate'},
              {'event_id': events[1]['event_id'], 'status': 'rejected'},
              {'event_id': 'not-in-batch', 'status': 'accepted'},
            ],
          }),
          200,
        );
      };
      await service.flush();
      expect(await box.batch('user-a', now), hasLength(1));
      expect(service.rejected.value, 1);
    },
  );

  test(
    'queue persists on disk, caps bytes/count and expires after seven days',
    () async {
      for (var i = 0; i < 4; i++) {
        await box.add(
          'user-a',
          {'event_id': 'event-$i'},
          now.add(Duration(seconds: i)),
          maxEvents: 2,
        );
      }
      expect((await box.batch('user-a', now)).map((e) => e['event_id']), [
        'event-2',
        'event-3',
      ]);
      await box.close();
      box = await AnalyticsOutbox.open(path: '${temp.path}/events.sqlite');
      expect(await box.batch('user-a', now), hasLength(2));
      expect(
        await box.batch('user-a', now.add(const Duration(days: 8))),
        isEmpty,
      );
      final dropped = await box.add(
        'user-a',
        {'event_id': 'large', 'data': 'a' * 100},
        now,
        maxBytes: 40,
      );
      expect(dropped, 1);
      expect(await box.batch('user-a', now), isEmpty);
    },
  );

  test(
    'defaults to off and debug builds neither collect nor open the production queue',
    () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        (await AppSettingsService().init()).analyticsEnabled.value,
        isFalse,
      );
      var opened = false;
      service = FeatureAnalyticsService(
        settings: settings,
        auth: auth,
        transport: service.transport,
        production: false,
        openOutbox: () async {
          opened = true;
          return box;
        },
      ).start();
      service.opened();
      expect(service.begin(AnalyticsSource.filePicker), isNull);
      await service.settled;
      await service.flush();
      expect(opened, isFalse);
      expect(batches, isEmpty);
    },
  );

  test('401 token race is rejected before sending a batch', () async {
    final token = Completer<String?>();
    var requests = 0;
    final transport = AnalyticsTransport(
      baseUrl: Uri.parse('https://amc.test'),
      readToken: () => token.future,
      clientFactory: () => MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    final future = transport.request(
      'events',
      body: {'expected_user_id': 'user-a', 'events': []},
    );
    transport.cancel();
    token.complete('token-of-user-b');
    await expectLater(future, throwsA(isA<AnalyticsHttpException>()));
    expect(requests, 0);
  });

  test(
    'AAB controller records business outcomes without private report or file data',
    () async {
      service.start();
      final checker = _BundleFixtureService(Directory('${temp.path}/reports'));
      final controller = BundleCheckController(
        service: checker,
        analytics: service,
      );
      addTearDown(controller.dispose);
      controller.stage = BundleCheckStage.checking;
      await controller.checkFile('ignored-while-busy.aab');
      controller.stage = BundleCheckStage.idle;
      await controller.checkFile('private-project.aab');
      expect(controller.stage, BundleCheckStage.done);
      checker.failRead = true;
      await controller.checkFile('private-file.aab');
      expect(controller.stage, BundleCheckStage.failed);
      await service.settled;
      final events = await box.batch('user-a', now);
      expect(
        events.where((e) => e['event_name'] == 'action.started'),
        hasLength(2),
      );
      expect(
        events.singleWhere(
          (e) => e['event_name'] == 'action.completed',
        )['result_category'],
        'issues_found',
      );
      expect(
        events.singleWhere(
          (e) => e['event_name'] == 'action.failed',
        )['error_code'],
        'file',
      );
      expect(jsonEncode(events), isNot(contains('private')));
    },
  );

  testWidgets(
    'dashboard shows untracked distinctly, filters requests, and hides data on account change',
    (tester) async {
      service.teams.assignAll([
        {'id': 'team-a', 'name': 'Team A'},
      ]);
      final queries = <String>[];
      respond = (r) {
        queries.add(r.url.query);
        return http.Response(
          jsonEncode({
            'active_users': 1,
            'coverage': 'Pilot coverage',
            'features': [
              {
                'id': 'bundle.check',
                'name': 'Kiểm tra AAB',
                'tracked': true,
                'users': 1,
                'eligible_users': 2,
                'uses': 1,
                'opens': 2,
                'completed': 1,
                'failed': 0,
                'unresolved': 0,
                'returning_users': 0,
              },
              {'id': 'qa.run', 'name': 'QA Desk', 'tracked': false},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      };
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final screenshotKey = GlobalKey();
      final screenshotPath = Platform.environment['ANALYTICS_SCREENSHOT'];
      if (screenshotPath != null) {
        await tester.runAsync(() async {
          final loader = FontLoader('AnalyticsQA')
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
                ),
              ),
            );
          await loader.load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: screenshotPath == null
              ? null
              : ThemeData(fontFamily: 'AnalyticsQA'),
          home: RepaintBoundary(
            key: screenshotKey,
            child: AnalyticsView(service: service),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chưa gắn tracking'), findsOneWidget);
      expect(find.text('50.0%'), findsOneWidget);
      expect(queries.last, contains('team=team-a'));
      if (screenshotPath != null) {
        final boundary =
            screenshotKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(screenshotPath).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('7 ngày'));
      await tester.pumpAndSettle();
      expect(queries.last, contains('days=7'));
      tester.view.physicalSize = const Size(420, 900);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      auth.profile.value = null;
      await tester.pumpAndSettle();
      expect(find.text('Kiểm tra AAB'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
