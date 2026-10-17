import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/safe_item.dart';
import '../services/safe_vault.dart';

enum SafeStage {
  /// Looking for the safe file.
  loading,

  /// No safe on this machine yet: the door asks for a new code.
  uncreated,
  locked,

  /// The code is being checked (Argon2id runs for a moment).
  unlocking,
  open,
}

/// Which compartment the interior shows.
sealed class SafeFilter {
  const SafeFilter();
}

class SafeFilterAll extends SafeFilter {
  const SafeFilterAll();

  @override
  bool operator ==(Object other) => other is SafeFilterAll;

  @override
  int get hashCode => 0;
}

class SafeFilterFavorites extends SafeFilter {
  const SafeFilterFavorites();

  @override
  bool operator ==(Object other) => other is SafeFilterFavorites;

  @override
  int get hashCode => 1;
}

class SafeFilterKind extends SafeFilter {
  const SafeFilterKind(this.kind);

  final SafeItemKind kind;

  @override
  bool operator ==(Object other) =>
      other is SafeFilterKind && other.kind == kind;

  @override
  int get hashCode => Object.hash(2, kind);
}

class SafeFilterProject extends SafeFilter {
  const SafeFilterProject(this.project);

  final String project;

  @override
  bool operator ==(Object other) =>
      other is SafeFilterProject && other.project == project;

  @override
  int get hashCode => Object.hash(3, project);
}

/// The one safe of this app run.
///
/// It outlives the page on purpose: closing the safe's screen to paste a
/// password somewhere and coming back should not ask for the code again,
/// unless the person chose that ([SafeSettings.lockOnClose]). The idle timer
/// is what shuts it.
class SafeController extends ChangeNotifier {
  SafeController({
    required SafeVault vault,
    DateTime Function()? now,
    Future<void> Function(String text)? writeClipboard,
    Future<String?> Function()? readClipboard,
  }) : _vault = vault,
       _now = now ?? DateTime.now,
       _writeClipboard = writeClipboard ?? _systemWriteClipboard,
       _readClipboard = readClipboard ?? _systemReadClipboard;

  static SafeController? _shared;

  /// The app-wide safe, created on first use.
  static SafeController get shared =>
      _shared ??= SafeController(vault: SafeVault.local());

  /// Shortest code accepted for a new safe.
  static const minimumCodeLength = 8;

  final SafeVault _vault;
  final DateTime Function() _now;
  final Future<void> Function(String text) _writeClipboard;
  final Future<String?> Function() _readClipboard;

  SafeStage _stage = SafeStage.loading;
  SafeStage get stage => _stage;

  /// What the door's display says: why it did not open, how long to wait.
  String _doorMessage = '';
  String get doorMessage => _doorMessage;

  /// Bumped on every refused code, so the door can shake once per refusal
  /// even when the message text does not change.
  int _refusals = 0;
  int get refusals => _refusals;

  int _failedAttempts = 0;
  int get failedAttempts => _failedAttempts;

  DateTime? _cooldownUntil;
  DateTime? get cooldownUntil => _cooldownUntil;
  Timer? _cooldownTimer;

  SafeSession? _session;
  SafeContents _contents = const SafeContents();
  List<SafeItem> get items => _contents.items;
  SafeSettings get settings => _contents.settings;

  bool _saving = false;
  bool get isSaving => _saving;

  /// Last failure of a save or a file operation inside the open safe.
  String _error = '';
  String get error => _error;

  SafeFilter _filter = const SafeFilterAll();
  SafeFilter get filter => _filter;

  String _query = '';
  String get query => _query;

  String? _selectedId;
  SafeItem? get selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  DateTime _lastActivity = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _autoLockTimer;

  /// When the door shuts by itself if nobody touches the safe.
  DateTime? get autoLockAt =>
      _stage == SafeStage.open ? _lastActivity.add(settings.autoLock) : null;

  String? _clipboardValue;
  Timer? _clipboardTimer;

  /// When the last copied secret is wiped from the clipboard, if pending.
  DateTime? _clipboardClearAt;
  DateTime? get clipboardClearAt => _clipboardClearAt;

  bool get isOpen => _stage == SafeStage.open;

  Future<String> get filePath => _vault.path;

  Future<void> load() async {
    if (_stage != SafeStage.loading) return;
    try {
      _stage = await _vault.exists() ? SafeStage.locked : SafeStage.uncreated;
    } catch (error) {
      _stage = SafeStage.locked;
      _doorMessage = 'Không đọc được két: $error';
    }
    notifyListeners();
  }

  /// Seals an empty safe under [code] and opens it.
  Future<bool> create(String code, String confirmation) async {
    if (_stage != SafeStage.uncreated) return false;
    final problem = validateNewCode(code, confirmation);
    if (problem != null) {
      _refuse(problem);
      return false;
    }
    _stage = SafeStage.unlocking;
    _doorMessage = 'Đang đúc khoá…';
    notifyListeners();
    try {
      _enter(await _vault.create(code));
      return true;
    } on SafeException catch (error) {
      _stage = SafeStage.uncreated;
      _refuse(error.message);
      return false;
    } catch (error) {
      _stage = SafeStage.uncreated;
      _refuse('Không tạo được két: $error');
      return false;
    }
  }

  Future<bool> unlock(String code) async {
    if (_stage != SafeStage.locked) return false;
    if (code.isEmpty) {
      _refuse('Nhập mã két.', countsAsAttempt: false);
      return false;
    }
    final wait = cooldownRemaining;
    if (wait > Duration.zero) {
      _refuse(
        'Két tạm khoá, thử lại sau ${wait.inSeconds + 1} giây.',
        countsAsAttempt: false,
      );
      return false;
    }

    _stage = SafeStage.unlocking;
    _doorMessage = 'Đang dò mã…';
    notifyListeners();
    try {
      _enter(await _vault.unlock(code));
      _failedAttempts = 0;
      _cooldownUntil = null;
      return true;
    } on SafeWrongCodeException catch (error) {
      _stage = SafeStage.locked;
      _failedAttempts++;
      final cooldown = _cooldownFor(_failedAttempts);
      if (cooldown > Duration.zero) {
        _cooldownUntil = _now().add(cooldown);
        _scheduleCooldownTick();
        _refuse(
          '${error.message} Sai $_failedAttempts lần, '
          'két tạm khoá ${cooldown.inSeconds} giây.',
        );
      } else {
        _refuse(error.message);
      }
      return false;
    } on SafeException catch (error) {
      _stage = SafeStage.locked;
      _refuse(error.message, countsAsAttempt: false);
      return false;
    } catch (error) {
      _stage = SafeStage.locked;
      _refuse('Không mở được két: $error', countsAsAttempt: false);
      return false;
    }
  }

  Duration get cooldownRemaining {
    final until = _cooldownUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  /// No wait for the first two slips, then a wait that grows: a person who
  /// mistyped barely notices, a script guessing codes crawls.
  static Duration _cooldownFor(int failures) => switch (failures) {
    < 3 => Duration.zero,
    3 => const Duration(seconds: 5),
    4 => const Duration(seconds: 15),
    5 => const Duration(seconds: 30),
    _ => const Duration(seconds: 60),
  };

  void _scheduleCooldownTick() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(cooldownRemaining, () {
      if (_stage == SafeStage.locked) {
        _doorMessage = 'Có thể thử lại.';
        notifyListeners();
      }
    });
  }

  static String? validateNewCode(String code, String confirmation) {
    if (code.length < minimumCodeLength) {
      return 'Mã két cần ít nhất $minimumCodeLength ký tự.';
    }
    if (code != confirmation) return 'Hai lần nhập mã không khớp.';
    return null;
  }

  void _enter(SafeOpened opened) {
    _session = opened.session;
    _contents = opened.contents;
    _stage = SafeStage.open;
    _doorMessage = '';
    _error = '';
    _selectedId = null;
    touch(force: true);
    notifyListeners();
  }

  void _refuse(String message, {bool countsAsAttempt = true}) {
    _doorMessage = message;
    if (countsAsAttempt) _refusals++;
    notifyListeners();
  }

  /// Shuts the door: the key is destroyed and every decrypted item dropped.
  Future<void> lock({String message = ''}) async {
    if (_stage != SafeStage.open) return;
    _autoLockTimer?.cancel();
    _session?.close();
    _session = null;
    _contents = const SafeContents();
    _selectedId = null;
    _query = '';
    _error = '';
    _stage = SafeStage.locked;
    _doorMessage = message;
    notifyListeners();
    await _wipeClipboardIfOurs();
  }

  /// The safe's page went away.
  Future<void> pageClosed() async {
    if (isOpen && settings.lockOnClose) await lock();
  }

  /// Records that someone is using the safe, pushing back the auto-lock.
  ///
  /// Called on every pointer and key event over the safe, so the timer is
  /// only rescheduled once a second.
  void touch({bool force = false}) {
    if (_stage != SafeStage.open) return;
    final now = _now();
    if (!force && now.difference(_lastActivity) < const Duration(seconds: 1)) {
      return;
    }
    _lastActivity = now;
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer(settings.autoLock, _autoLockFired);
  }

  void _autoLockFired() {
    final deadline = autoLockAt;
    if (deadline == null) return;
    // A timer can fire early on a busy loop; re-arm for what is left.
    final left = deadline.difference(_now());
    if (left > Duration.zero) {
      _autoLockTimer = Timer(left, _autoLockFired);
      return;
    }
    unawaited(
      lock(
        message: 'Két tự khoá sau ${settings.autoLockMinutes} phút không dùng.',
      ),
    );
  }

  // ---- inside the safe ----------------------------------------------------

  void setFilter(SafeFilter filter) {
    if (_filter == filter) return;
    _filter = filter;
    notifyListeners();
  }

  void setQuery(String query) {
    if (_query == query) return;
    _query = query;
    notifyListeners();
  }

  void select(String? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  /// The items of the current compartment matching the search, favourites
  /// first, then most recently changed.
  List<SafeItem> get visibleItems {
    final query = _query.trim().toLowerCase();
    final result = items.where((item) {
      final inCompartment = switch (_filter) {
        SafeFilterAll() => true,
        SafeFilterFavorites() => item.favorite,
        SafeFilterKind(:final kind) => item.kind == kind,
        SafeFilterProject(:final project) => item.project == project,
      };
      if (!inCompartment) return false;
      if (query.isEmpty) return true;
      return query
          .split(RegExp(r'\s+'))
          .every((word) => item.searchText.contains(word));
    }).toList();
    result.sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return result;
  }

  int countFor(SafeFilter filter) => switch (filter) {
    SafeFilterAll() => items.length,
    SafeFilterFavorites() => items.where((item) => item.favorite).length,
    SafeFilterKind(:final kind) =>
      items.where((item) => item.kind == kind).length,
    SafeFilterProject(:final project) =>
      items.where((item) => item.project == project).length,
  };

  /// Every project something in the safe belongs to, by name.
  List<String> get projects {
    final names = {
      for (final item in items)
        if (item.project.isNotEmpty) item.project,
    }.toList();
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  /// A blank item of [kind], not yet in the safe.
  SafeItem draft(SafeItemKind kind) {
    final now = _now();
    return SafeItem(
      id: const Uuid().v4(),
      kind: kind,
      title: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Adds [item], or replaces the item with its id.
  Future<bool> put(SafeItem item) async {
    final stamped = item.copyWith(updatedAt: _now());
    final index = items.indexWhere((existing) => existing.id == item.id);
    final next = [...items];
    if (index >= 0) {
      next[index] = stamped;
    } else {
      next.add(stamped);
    }
    final saved = await _persist(_contents.copyWith(items: next));
    if (saved) _selectedId = item.id;
    notifyListeners();
    return saved;
  }

  /// Adds many items with one write, as a folder scan does.
  Future<bool> putAll(List<SafeItem> added) async {
    if (added.isEmpty) return true;
    final now = _now();
    final byId = {for (final item in items) item.id: item};
    for (final item in added) {
      byId[item.id] = item.copyWith(updatedAt: now);
    }
    final saved = await _persist(
      _contents.copyWith(items: byId.values.toList()),
    );
    notifyListeners();
    return saved;
  }

  Future<bool> remove(String id) async {
    final next = items.where((item) => item.id != id).toList();
    final saved = await _persist(_contents.copyWith(items: next));
    if (saved && _selectedId == id) _selectedId = null;
    if (_filter is SafeFilterProject && countFor(_filter) == 0) {
      _filter = const SafeFilterAll();
    }
    notifyListeners();
    return saved;
  }

  Future<bool> toggleFavorite(String id) async {
    final next = [
      for (final item in items)
        item.id == id ? item.copyWith(favorite: !item.favorite) : item,
    ];
    return _persist(_contents.copyWith(items: next));
  }

  Future<bool> updateSettings(SafeSettings settings) async {
    final saved = await _persist(_contents.copyWith(settings: settings));
    if (saved) touch(force: true);
    return saved;
  }

  Future<String?> changeCode(
    String currentCode,
    String newCode,
    String confirmation,
  ) async {
    final session = _session;
    if (session == null) return 'Két đã khoá.';
    final problem = validateNewCode(newCode, confirmation);
    if (problem != null) return problem;
    _saving = true;
    notifyListeners();
    try {
      _session = await _vault.changeCode(
        session,
        currentCode,
        newCode,
        _contents,
      );
      return null;
    } on SafeWrongCodeException {
      return 'Mã két hiện tại không đúng.';
    } on SafeException catch (error) {
      return error.message;
    } catch (error) {
      return 'Không đổi được mã: $error';
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<String?> exportBackup(String destination) async {
    try {
      await _vault.exportBackup(destination);
      return null;
    } catch (error) {
      return 'Không xuất được bản sao lưu: $error';
    }
  }

  /// Opens [source] with [code] and makes it this machine's safe.
  Future<String?> restoreBackup(String source, String code) async {
    try {
      final opened = await _vault.restoreBackup(source, code);
      _session?.close();
      _enter(opened);
      return null;
    } on SafeWrongCodeException {
      return 'Mã không mở được bản sao lưu này.';
    } on SafeException catch (error) {
      return error.message;
    } catch (error) {
      return 'Không khôi phục được: $error';
    }
  }

  Future<bool> _persist(SafeContents next) async {
    final session = _session;
    if (session == null) return false;
    _saving = true;
    notifyListeners();
    try {
      await _vault.save(session, next);
      _contents = next;
      _error = '';
      return true;
    } catch (error) {
      _error = 'Không lưu được vào két: $error';
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  // ---- clipboard ----------------------------------------------------------

  /// Copies [value] and wipes it from the clipboard after
  /// [SafeSettings.clipboardSeconds], unless something else was copied since.
  Future<void> copySecret(String value) async {
    await _writeClipboard(value);
    _clipboardValue = value;
    _clipboardTimer?.cancel();
    final delay = settings.clipboardClear;
    _clipboardClearAt = _now().add(delay);
    _clipboardTimer = Timer(delay, () => unawaited(_wipeClipboardIfOurs()));
    touch();
    notifyListeners();
  }

  Future<void> _wipeClipboardIfOurs() async {
    _clipboardTimer?.cancel();
    final ours = _clipboardValue;
    _clipboardValue = null;
    _clipboardClearAt = null;
    if (ours == null) return;
    try {
      if (await _readClipboard() == ours) await _writeClipboard('');
    } catch (error) {
      debugPrint('Could not clear the clipboard: $error');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    _cooldownTimer?.cancel();
    _clipboardTimer?.cancel();
    _session?.close();
    super.dispose();
  }

  static Future<void> _systemWriteClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  static Future<String?> _systemReadClipboard() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;
}
