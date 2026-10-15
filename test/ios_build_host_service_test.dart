import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/models/ios_release.dart';
import 'package:app_management_center/app/services/ios_build_envelope.dart';
import 'package:app_management_center/app/services/ios_build_host_service.dart';
import 'package:app_management_center/app/services/ios_release_workflow_service.dart';
import 'package:app_management_center/app/services/remote_ios_release_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'ios_build_host_fakes.dart';

void main() {
  const desktopId = 'mac-test';
  late Directory temp;
  late TestRepository repository;
  late FakeMacRunner runner;
  late IosBuildHostService host;
  var now = DateTime.now();

  setUp(() async {
    now = DateTime.now();
    temp = await Directory.systemTemp.createTemp('ios_build_host_test_');
    repository = await TestRepository.create(temp);
    runner = FakeMacRunner();
    host = IosBuildHostService(
      runner: runner,
      secureStore: MemorySecureStore(),
      root: Directory(p.join(temp.path, 'host')),
      workspaces: Directory(p.join(temp.path, 'workspaces')),
      isMacOS: () => true,
      now: () => now,
      allowLocalRemotes: true,
    );
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {
      // Windows can hold a handle on a git object for a moment.
    }
  });

  Map<String, Object?> body({
    String? commit,
    List<Map<String, Object?>>? files,
    Map<String, Object?> extra = const {},
  }) => {
    'project': {
      'id': 'app',
      'displayName': 'Demo',
      'bundleId': 'com.example.demo',
    },
    'credentials': {
      'p8PrivateKey': 'PRIVATE TEST FIXTURE',
      'keyId': 'KEY',
      'issuerId': 'ISSUER',
      'teamId': 'TEAM',
    },
    'settings': const IosReleaseSettings(
      teamId: 'TEAM',
      remoteFiles: ['.env'],
      flutterExecutable: r'C:\flutter\bin\flutter.bat',
    ).toJson(),
    'git': {'remote': repository.origin, 'commit': commit ?? repository.commit},
    'files':
        files ??
        [
          {'path': '.env', 'data': base64.encode(utf8.encode('API=prod\n'))},
        ],
    ...extra,
  };

  Future<Map<String, Object?>> payload(
    String action,
    Map<String, Object?> content, {
    String runId = '',
    String? sealedAs,
    Duration lifetime = const Duration(hours: 1),
  }) async => {
    'action': action,
    'runId': runId,
    'projectId': 'app',
    'envelope': await IosBuildEnvelope.seal(
      hostPublicKey: await host.publicKey(),
      body: {
        ...content,
        'id': IosBuildEnvelope.randomId(),
        'exp': now.add(lifetime).toUtc().toIso8601String(),
      },
      associatedData: IosBuildEnvelope.associatedData(
        desktopId: desktopId,
        action: sealedAs ?? action,
        runId: runId,
        projectId: 'app',
      ),
    ),
  };

  Future<IosReleaseRun> run(
    String action,
    Map<String, Object?> content, {
    String runId = '',
  }) async {
    final outcome = await host.execute(
      desktopId: desktopId,
      payload: await payload(action, content, runId: runId),
    );
    return iosRunFromWire(
      Map<String, dynamic>.from(outcome.result['run']! as Map),
    );
  }

  test(
    'prepares from the commit on origin with gitignored files sent along',
    () async {
      final prepared = await run('prepare', body());

      expect(prepared.status, IosReleaseStatus.prepared);
      expect(prepared.commit, repository.commit);
      expect(prepared.dirty, isFalse);
      expect(prepared.version, '1.2.3');
      expect(prepared.buildNumber, 11);
      // The sender's Flutter path means nothing on the Mac.
      expect(prepared.settings.flutterExecutable, isEmpty);
      final workspace = prepared.project.path;
      expect(p.isWithin(p.join(temp.path, 'workspaces'), workspace), isTrue);
      expect(
        await File(p.join(workspace, '.env')).readAsString(),
        'API=prod\n',
      );
      expect(await git(['rev-parse', 'HEAD'], workspace), repository.commit);
    },
  );

  test('runs the rest of TestFlight and the App Store on that run', () async {
    final prepared = await run('prepare', body());
    final ready = await run('continue', body(), runId: prepared.id);
    expect(ready.status, IosReleaseStatus.ready);
    expect(runner.buildCalls, 1);
    expect(runner.appleActions, contains('upload'));
    expect(ready.store.findBuild('1.2.3', 11)?.isReady, isTrue);

    final draft = await run('draft', body(), runId: prepared.id);
    expect(draft.status, IosReleaseStatus.draft);
    // Credentials are held for a step, not kept between them.
    expect(runner.appleActions.last, 'draft');
  });

  test('refuses an envelope it has already run', () async {
    final sent = await payload('prepare', body());
    await host.execute(desktopId: desktopId, payload: sent);
    await expectLater(
      host.execute(desktopId: desktopId, payload: sent),
      throwsA(
        isA<IosBuildHostException>().having(
          (error) => error.message,
          'message',
          contains('đã được chạy'),
        ),
      ),
    );
  });

  test('refuses a sealed step relabelled as another', () async {
    final prepared = await run('prepare', body());
    await expectLater(
      host.execute(
        desktopId: desktopId,
        payload: await payload(
          'submit',
          body(),
          runId: prepared.id,
          sealedAs: 'draft',
        ),
      ),
      throwsA(isA<IosBuildHostException>()),
    );
    expect(runner.appleActions, isNot(contains('submit')));
  });

  test('refuses an expired step', () async {
    await expectLater(
      host.execute(
        desktopId: desktopId,
        payload: await payload(
          'prepare',
          body(),
          lifetime: const Duration(seconds: -1),
        ),
      ),
      throwsA(
        isA<IosBuildHostException>().having(
          (error) => error.message,
          'message',
          contains('quá hạn'),
        ),
      ),
    );
  });

  test('a commit that never reached origin is refused', () async {
    await File(
      p.join(repository.clone, 'lib', 'main.dart'),
    ).writeAsString('void main() { print(1); }\n');
    await git(['commit', '-qam', 'local only'], repository.clone);
    final local = await git(['rev-parse', 'HEAD'], repository.clone);

    await expectLater(
      run('prepare', body(commit: local)),
      throwsA(
        isA<IosBuildHostException>().having(
          (error) => error.message,
          'message',
          contains('chưa có trên origin'),
        ),
      ),
    );

    // Pushing is all it takes.
    await git(['push', '-q', 'origin', 'main'], repository.clone);
    expect((await run('prepare', body(commit: local))).commit, local);
  });

  test('will not overwrite a tracked file with one sent along', () async {
    await expectLater(
      run(
        'prepare',
        body(
          files: [
            {
              'path': 'pubspec.yaml',
              'data': base64.encode([1, 2, 3]),
            },
          ],
        ),
      ),
      throwsA(
        isA<IosBuildHostException>().having(
          (error) => error.message,
          'message',
          contains('.gitignore'),
        ),
      ),
    );
    for (final path in ['../escape.env', '.git/config', r'C:\x.env']) {
      await expectLater(
        run(
          'prepare',
          body(
            files: [
              {'path': path, 'data': ''},
            ],
          ),
        ),
        throwsA(isA<IosBuildHostException>()),
        reason: path,
      );
    }
  });

  test('a new release starts from the commit, not from leftovers', () async {
    final first = await run('prepare', body());
    final workspace = first.project.path;
    await File(p.join(workspace, 'pubspec.yaml')).writeAsString('changed\n');
    await File(p.join(workspace, 'stray.txt')).writeAsString('left behind');

    final second = await run('prepare', body());

    expect(second.project.path, workspace);
    expect(second.dirty, isFalse);
    expect(
      await File(p.join(workspace, 'pubspec.yaml')).readAsString(),
      contains('version: 1.2.3+10'),
    );
    expect(File(p.join(workspace, 'stray.txt')).existsSync(), isFalse);
    // Ignored files survive the reset.
    expect(File(p.join(workspace, '.env')).existsSync(), isTrue);
  });

  test('a workspace pointing at another repository is left alone', () async {
    final prepared = await run('prepare', body());
    await git([
      'remote',
      'set-url',
      'origin',
      p.join(temp.path, 'elsewhere.git'),
    ], prepared.project.path);

    await expectLater(
      run('prepare', body()),
      throwsA(
        isA<IosBuildHostException>().having(
          (error) => error.message,
          'message',
          contains('đang trỏ tới'),
        ),
      ),
    );
  });

  test('answers history and log questions for the project', () async {
    final prepared = await run('prepare', body());

    final history = await host.query({'action': 'history', 'projectId': 'app'});
    final runs = history.result['runs']! as List;
    expect(runs, hasLength(1));
    expect((runs.single as Map)['id'], prepared.id);
    expect(history.result['busy'], isFalse);

    final other = await host.query({
      'action': 'history',
      'projectId': 'another-app',
    });
    expect(other.result['runs'], isEmpty);

    final log = await host.query({
      'action': 'log',
      'projectId': 'app',
      'runId': prepared.id,
    });
    expect(log.logLines.join('\n'), contains('xcodebuild'));
    expect(log.logLines.join('\n'), isNot(contains('PRIVATE TEST FIXTURE')));
  });

  test('advertises its key only while switched on', () async {
    expect(await host.heartbeat(enabled: false), {'enabled': false});
    final state = await host.heartbeat(enabled: true);
    expect(state['enabled'], isTrue);
    expect(base64.decode(state['publicKey']! as String), hasLength(32));
    expect(state['fingerprint'], await host.fingerprint());
  });

  group('input checks', () {
    test('only clones remotes that cannot run anything', () {
      for (final remote in [
        'https://github.com/org/app.git',
        'git@github.com:org/app.git',
        'ssh://git@bitbucket.org:7999/org/app.git',
      ]) {
        expect(IosBuildHostService.isAllowedGitRemote(remote), isTrue);
      }
      for (final remote in [
        'https://user:token@github.com/org/app.git',
        'ext::sh -c touch% /tmp/pwned',
        'file:///Users/me/app',
        '/Users/me/app',
        '-uhttps://x/y',
        'http://github.com/org/app.git',
        '',
      ]) {
        expect(
          IosBuildHostService.isAllowedGitRemote(remote),
          isFalse,
          reason: remote,
        );
      }
    });

    test('the sender strips a token from its remote before sending', () {
      expect(
        RemoteIosReleaseService.sanitizeRemote(
          'https://me:ghp_secret@github.com/org/app.git',
        ),
        'https://github.com/org/app.git',
      );
      expect(
        RemoteIosReleaseService.sanitizeRemote('git@github.com:org/app.git'),
        'git@github.com:org/app.git',
      );
    });

    test('files sent along stay inside the project', () {
      expect(IosReleaseWorkflowService.remoteFilePath(r'ios\.env'), 'ios/.env');
      expect(IosReleaseWorkflowService.remoteFilePath('./.env'), '.env');
      for (final path in ['', '/etc/hosts', '../x', 'a/../../x', '.git/x']) {
        expect(
          IosReleaseWorkflowService.remoteFilePath(path),
          isNull,
          reason: path,
        );
      }
    });

    test('an absolute ExportOptions path is refused on the Mac', () {
      expect(
        () => IosBuildHostService.hostSettings(
          const IosReleaseSettings(
            exportOptionsPath: r'C:\signing\ExportOptions.plist',
          ).toJson(),
        ),
        throwsA(isA<IosBuildHostException>()),
      );
      expect(
        IosBuildHostService.hostSettings(
          const IosReleaseSettings(
            exportOptionsPath: 'ios/ExportOptions.plist',
          ).toJson(),
        ).exportOptionsPath,
        'ios/ExportOptions.plist',
      );
    });
  });
}
