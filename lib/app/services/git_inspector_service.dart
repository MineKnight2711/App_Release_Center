import 'dart:io';

import 'package:get/get.dart';

/// What a repository can offer a "pull branch" prompt, read straight from git.
///
/// Empty lists are a normal answer: the directory may not be a repository, or
/// git may not be installed. Callers fall back to free text in that case rather
/// than blocking.
class GitBranchOptions {
  const GitBranchOptions({
    this.remotes = const [],
    this.branchesByRemote = const {},
    this.currentBranch,
    this.suggestedRemote,
    this.suggestedBranch,
  });

  final List<String> remotes;

  /// Remote name to the branch names it publishes, without the `remote/`
  /// prefix and without the `HEAD` alias.
  final Map<String, List<String>> branchesByRemote;

  /// The checked-out branch, or null when HEAD is detached.
  final String? currentBranch;

  /// What to preselect: the current branch's upstream when it has one, else
  /// `origin` if present, else the first remote.
  final String? suggestedRemote;

  /// What to preselect: the upstream branch, else a remote branch matching the
  /// checked-out one, else the first branch of [suggestedRemote].
  final String? suggestedBranch;

  bool get isEmpty => remotes.isEmpty;

  List<String> branchesFor(String remote) =>
      branchesByRemote[remote] ?? const [];
}

/// Reads the facts a prompt would otherwise ask the user to type.
///
/// Every probe is a short read-only git call run outside [ReleaseRunnerService]
/// on purpose: these run while a dialog is opening, so they must not take the
/// runner's single-command slot or write to the command log.
class GitInspectorService extends GetxService {
  GitInspectorService();

  static const _timeout = Duration(seconds: 10);

  Future<GitBranchOptions> readBranchOptions(String projectPath) async {
    if (!Directory(projectPath).existsSync()) {
      return const GitBranchOptions();
    }

    final remotes = await _lines(projectPath, ['remote']);
    if (remotes.isEmpty) return const GitBranchOptions();

    final remoteRefs = await _lines(projectPath, [
      'branch',
      '--remotes',
      '--format=%(refname:short)',
    ]);

    final branchesByRemote = <String, List<String>>{
      for (final remote in remotes) remote: <String>[],
    };
    for (final ref in remoteRefs) {
      // Skip the `origin/HEAD -> origin/main` alias; it is not a branch.
      if (ref.contains('->')) continue;
      final separator = ref.indexOf('/');
      if (separator <= 0) continue;
      final remote = ref.substring(0, separator);
      final branch = ref.substring(separator + 1);
      if (branch.isEmpty || branch == 'HEAD') continue;
      branchesByRemote[remote]?.add(branch);
    }
    for (final entry in branchesByRemote.entries) {
      entry.value.sort();
    }

    final head = await _first(projectPath, [
      'rev-parse',
      '--abbrev-ref',
      'HEAD',
    ]);
    final currentBranch = (head == null || head == 'HEAD') ? null : head;

    final upstream = await _first(projectPath, [
      'rev-parse',
      '--abbrev-ref',
      '--symbolic-full-name',
      '@{upstream}',
    ]);

    String? suggestedRemote;
    String? suggestedBranch;
    if (upstream != null) {
      final separator = upstream.indexOf('/');
      if (separator > 0) {
        final remote = upstream.substring(0, separator);
        if (remotes.contains(remote)) {
          suggestedRemote = remote;
          suggestedBranch = upstream.substring(separator + 1);
        }
      }
    }

    suggestedRemote ??= remotes.contains('origin') ? 'origin' : remotes.first;
    final candidates = branchesByRemote[suggestedRemote] ?? const <String>[];
    if (suggestedBranch == null || !candidates.contains(suggestedBranch)) {
      if (currentBranch != null && candidates.contains(currentBranch)) {
        suggestedBranch = currentBranch;
      } else {
        suggestedBranch = candidates.isEmpty ? null : candidates.first;
      }
    }

    return GitBranchOptions(
      remotes: remotes,
      branchesByRemote: branchesByRemote,
      currentBranch: currentBranch,
      suggestedRemote: suggestedRemote,
      suggestedBranch: suggestedBranch,
    );
  }

  Future<List<String>> _lines(
    String projectPath,
    List<String> arguments,
  ) async {
    final output = await _run(projectPath, arguments);
    if (output == null) return const [];
    return output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<String?> _first(String projectPath, List<String> arguments) async {
    final lines = await _lines(projectPath, arguments);
    return lines.isEmpty ? null : lines.first;
  }

  Future<String?> _run(String projectPath, List<String> arguments) async {
    try {
      final result = await Process.run(
        'git',
        arguments,
        workingDirectory: projectPath,
        runInShell: true,
      ).timeout(_timeout);
      if (result.exitCode != 0) return null;
      return result.stdout.toString();
    } catch (_) {
      // A missing git, a non-repository, or a hung call all mean the same
      // thing here: no suggestion to offer.
      return null;
    }
  }
}
