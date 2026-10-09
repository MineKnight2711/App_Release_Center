import 'dart:io';

import '../models/qa_models.dart';

class GitMetadataService {
  const GitMetadataService();

  Future<GitMetadata> read(String workingDirectory) async {
    try {
      final branch = await _git(workingDirectory, [
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
      ]);
      final commit = await _git(workingDirectory, [
        'rev-parse',
        '--short',
        'HEAD',
      ]);
      final status = await _git(workingDirectory, ['status', '--porcelain']);
      return GitMetadata(
        branch: branch.isEmpty ? null : branch,
        commit: commit.isEmpty ? null : commit,
        isDirty: status.isNotEmpty,
      );
    } on Object {
      return const GitMetadata();
    }
  }

  Future<String> _git(String workingDirectory, List<String> arguments) async {
    final result = await Process.run('git', [
      '-C',
      workingDirectory,
      ...arguments,
    ], runInShell: false);
    if (result.exitCode != 0) throw StateError('Not a Git repository');
    return result.stdout.toString().trim();
  }
}
