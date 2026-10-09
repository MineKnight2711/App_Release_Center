import 'package:flutter/foundation.dart';

import 'account_vault.dart';

/// What QA Desk needs to know about the rest of AMC, without depending on its
/// controllers. AMC sets one at startup on `QaDeskRuntime.host`.
abstract class QaDeskHost {
  const QaDeskHost();

  /// The project folder open in AMC, if any.
  String? get currentProjectPath;

  /// AMC's recent project folders, newest first, as its project panel lists
  /// them.
  List<String> get recentProjectPaths;

  /// Project folders AMC is running a release or script in right now.
  Iterable<String> get busyProjectPaths;

  /// Fires when [busyProjectPaths] changes.
  Listenable get changes;

  /// The signed-in team member, or null when AMC is not signed in to a team:
  /// the demo-account vault is then kept on this machine only.
  QaTeamContext? get team => null;

  /// Where [team]'s shared vault is stored, or null to keep it on this
  /// machine.
  VaultBackend? teamVaultBackend(String teamId) => null;
}

/// Who is signed in to AMC's team, for the shared demo-account vault.
class QaTeamContext {
  const QaTeamContext({
    required this.teamId,
    required this.teamName,
    required this.uid,
    required this.email,
    required this.isAdmin,
  });

  final String teamId;
  final String teamName;
  final String uid;
  final String email;
  final bool isAdmin;
}

/// The host when nothing in AMC has registered one: tests, and QA Desk on its
/// own.
class StandaloneQaDeskHost extends QaDeskHost {
  const StandaloneQaDeskHost();

  @override
  String? get currentProjectPath => null;

  @override
  List<String> get recentProjectPaths => const [];

  @override
  Iterable<String> get busyProjectPaths => const [];

  @override
  Listenable get changes => const _Silent();
}

class _Silent implements Listenable {
  const _Silent();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
