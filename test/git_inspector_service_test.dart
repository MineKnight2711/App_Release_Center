import 'dart:io';

import 'package:app_management_center/app/services/git_inspector_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory origin;
  late Directory clone;
  final service = GitInspectorService();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('arc_git_inspector_');
    origin = Directory(p.join(root.path, 'origin.git'));
    clone = Directory(p.join(root.path, 'clone'));
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('returns nothing for a directory that is not a repository', () async {
    final options = await service.readBranchOptions(root.path);

    expect(options.isEmpty, isTrue);
    expect(options.remotes, isEmpty);
    expect(options.suggestedRemote, isNull);
  });

  test('returns nothing for a path that does not exist', () async {
    final options = await service.readBranchOptions(
      p.join(root.path, 'missing'),
    );

    expect(options.isEmpty, isTrue);
  });

  test('reads remotes, branches and the upstream suggestion', () async {
    if (!await _gitIsAvailable()) {
      markTestSkipped('git is not on PATH');
      return;
    }

    await _seedOrigin(origin, root);
    await _run(root.path, ['clone', origin.path, clone.path]);
    await _run(clone.path, ['config', 'user.email', 'test@example.com']);
    await _run(clone.path, ['config', 'user.name', 'Test']);
    await _run(clone.path, ['checkout', '-B', 'develop', 'origin/develop']);

    final options = await service.readBranchOptions(clone.path);

    expect(options.remotes, ['origin']);
    expect(options.branchesFor('origin'), containsAll(['develop', 'main']));
    // The HEAD alias is not a branch anyone can pull by name.
    expect(options.branchesFor('origin'), isNot(contains('HEAD')));
    expect(options.currentBranch, 'develop');
    expect(options.suggestedRemote, 'origin');
    expect(options.suggestedBranch, 'develop');
  });

  test('falls back to origin when the branch has no upstream', () async {
    if (!await _gitIsAvailable()) {
      markTestSkipped('git is not on PATH');
      return;
    }

    await _seedOrigin(origin, root);
    await _run(root.path, ['clone', origin.path, clone.path]);
    await _run(clone.path, ['config', 'user.email', 'test@example.com']);
    await _run(clone.path, ['config', 'user.name', 'Test']);
    // A local-only branch: no upstream to read.
    await _run(clone.path, ['checkout', '-b', 'scratch']);

    final options = await service.readBranchOptions(clone.path);

    expect(options.currentBranch, 'scratch');
    expect(options.suggestedRemote, 'origin');
    expect(options.suggestedBranch, isNotNull);
    expect(options.branchesFor('origin'), contains(options.suggestedBranch));
  });
}

Future<bool> _gitIsAvailable() async {
  try {
    final result = await Process.run('git', ['--version'], runInShell: true);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Builds a bare repo with `main` and `develop` to clone from.
Future<void> _seedOrigin(Directory origin, Directory root) async {
  final work = Directory(p.join(root.path, 'seed'))
    ..createSync(recursive: true);
  await _run(root.path, [
    'init',
    '--bare',
    '--initial-branch=main',
    origin.path,
  ]);
  await _run(root.path, ['init', '--initial-branch=main', work.path]);
  await _run(work.path, ['config', 'user.email', 'test@example.com']);
  await _run(work.path, ['config', 'user.name', 'Test']);
  File(p.join(work.path, 'README.md')).writeAsStringSync('seed\n');
  await _run(work.path, ['add', '.']);
  await _run(work.path, ['commit', '-m', 'seed']);
  await _run(work.path, ['remote', 'add', 'origin', origin.path]);
  await _run(work.path, ['push', 'origin', 'main']);
  await _run(work.path, ['checkout', '-b', 'develop']);
  await _run(work.path, ['push', 'origin', 'develop']);
}

Future<void> _run(String workingDirectory, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: workingDirectory,
    runInShell: true,
  );
  if (result.exitCode != 0) {
    throw StateError(
      'git ${arguments.join(' ')} failed (${result.exitCode}): ${result.stderr}',
    );
  }
}
