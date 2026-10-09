import 'package:app_management_center/app/controllers/home_controller.dart';
import 'package:app_management_center/app/models/auth_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/qa_desk_host.dart';
import 'package:app_management_center/app/services/auth_service.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

/// Tells QA Desk what the rest of AMC is doing: which project is open, which
/// ones are recent, and whether a release is running in one.
///
/// The home controller is resolved on each read rather than held, because it
/// is registered lazily and this host is created before the shell builds it.
class AmcQaDeskHost extends ChangeNotifier implements QaDeskHost {
  AmcQaDeskHost({
    required ReleaseRunnerService runner,
    required HomeController Function() home,
  }) : _runner = runner,
       _home = home {
    _workers = [
      ever<bool>(runner.isRunning, (_) => notifyListeners()),
      ever<bool>(runner.isWorkflowRunning, (_) => notifyListeners()),
    ];
  }

  final ReleaseRunnerService _runner;
  final HomeController Function() _home;
  late final List<Worker> _workers;

  @override
  String? get currentProjectPath => _home().project.value?.path;

  @override
  List<String> get recentProjectPaths => _home().recentPaths.toList();

  /// Every release command runs in the open project, so that is the one a
  /// busy runner is using.
  @override
  Iterable<String> get busyProjectPaths {
    final path = currentProjectPath;
    return _runner.isBusy && path != null ? [path] : const [];
  }

  @override
  Listenable get changes => this;

  /// The signed-in member of AMC's team, for the shared demo-account vault.
  @override
  QaTeamContext? get team {
    if (!Get.isRegistered<AuthService>()) return null;
    final profile = Get.find<AuthService>().profile.value;
    if (profile == null || profile.teamId.isEmpty) return null;
    return QaTeamContext(
      teamId: profile.teamId,
      teamName: profile.teamName,
      uid: profile.uid,
      email: profile.email,
      isAdmin: profile.role == TeamRole.admin,
    );
  }

  @override
  void dispose() {
    for (final worker in _workers) {
      worker.dispose();
    }
    super.dispose();
  }
}
