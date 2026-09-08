import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:get/get.dart';

/// Which tab the Automation panel shows.
enum ShellFlowTab { storeVersions, fastlaneFlow, fastlaneCommand }

/// Which tab the Options panel shows.
enum ShellOptionsTab { release, setup, resources, telegram, push, remote }

/// Owns the shell-level UI state that used to live implicitly inside the two
/// `DefaultTabController`s: which tab each panel shows, and whether the command
/// palette is open.
///
/// It is deliberately separate from [HomeController]: the palette needs to
/// steer navigation from anywhere, and routing that through a 4k-line
/// controller would make it harder to break that file up later.
class AppShellController extends GetxController {
  AppShellController({required this.store});

  final ProjectStoreService store;

  final flowTab = ShellFlowTab.storeVersions.obs;
  final optionsTab = ShellOptionsTab.release.obs;
  final isPaletteOpen = false.obs;

  /// Command palette entries the user ran most recently, newest first. Drives
  /// the palette's default list so the common case needs no typing at all.
  final recentCommandIds = <String>[].obs;

  @override
  void onInit() {
    super.onInit();
    recentCommandIds.assignAll(store.recentCommandIds);
  }

  void showFlowTab(ShellFlowTab tab) => flowTab.value = tab;

  void showOptionsTab(ShellOptionsTab tab) => optionsTab.value = tab;

  void openPalette() => isPaletteOpen.value = true;

  void closePalette() => isPaletteOpen.value = false;

  void togglePalette() => isPaletteOpen.toggle();

  /// Moves [commandId] to the front of the recent list and persists it.
  ///
  /// Ids of transient commands (a Fastlane lane in a project that is no longer
  /// open, say) are kept as written; the palette drops the ones it can no
  /// longer resolve when it builds its list.
  Future<void> markCommandUsed(String commandId) async {
    if (commandId.isEmpty) return;
    final next = <String>[
      commandId,
      ...recentCommandIds.where((id) => id != commandId),
    ];
    recentCommandIds.assignAll(next);
    await store.saveRecentCommandIds(recentCommandIds);
    recentCommandIds.assignAll(store.recentCommandIds);
  }
}
