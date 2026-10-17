import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/safe_item.dart';
import '../services/safe_secret_scanner.dart';
import 'safe_controller.dart';

enum SafeScanStage { idle, scanning, done }

/// What an import put into the safe.
class SafeScanImport {
  const SafeScanImport({
    required this.imported,
    required this.projects,
    required this.failed,
  });

  final int imported;
  final int projects;

  /// Files that could not be read any more, by path.
  final List<String> failed;
}

/// One folder scan, from picking folders to putting the chosen findings in
/// the safe.
///
/// Every finding starts ticked, as the person asked, except those already in
/// the safe: they are recognised by fingerprint and cannot be ticked, so a
/// second scan of the same folders adds only what is new.
class SafeScanController extends ChangeNotifier {
  SafeScanController({
    required this.safe,
    SecretScanRunner? runner,
    Future<List<int>> Function(String path)? readFile,
  }) : _runner = runner ?? SafeSecretScanner.start,
       _readFile = readFile ?? ((path) => File(path).readAsBytes()) {
    _known = {
      for (final item in safe.items)
        if (item.secret.isNotEmpty)
          item.kind == SafeItemKind.file
              ? fingerprintBytes(item.fileBytes)
              : fingerprintBytes(utf8.encode(item.secret)),
    };
  }

  final SafeController safe;
  final SecretScanRunner _runner;
  final Future<List<int>> Function(String path) _readFile;
  late final Set<String> _known;

  SafeScanStage _stage = SafeScanStage.idle;
  SafeScanStage get stage => _stage;

  final _roots = <String>[];
  List<String> get roots => List.unmodifiable(_roots);

  final _projects = <SecretProject>[];
  List<SecretProject> get projects => List.unmodifiable(_projects);

  SecretScanProgress? _progress;
  SecretScanProgress? get progress => _progress;

  String _error = '';
  String get error => _error;

  final _tooLarge = <String>{};
  List<String> get tooLarge => _tooLarge.toList();

  bool _truncated = false;
  bool get truncated => _truncated;

  SecretScanJob? _job;
  bool _importing = false;
  bool get isImporting => _importing;

  final _selected = <String>{};
  final _collapsed = <String>{};
  final _hiddenTypes = <SecretFindingType>{};
  String _query = '';
  String get query => _query;

  static String _key(SecretProject project, SecretFinding finding) =>
      '${project.root}\u0000${finding.id}';

  bool isKnown(SecretFinding finding) => _known.contains(finding.fingerprint);

  bool isSelected(SecretProject project, SecretFinding finding) =>
      _selected.contains(_key(project, finding));

  bool isCollapsed(SecretProject project) => _collapsed.contains(project.root);

  bool isTypeShown(SecretFindingType type) => !_hiddenTypes.contains(type);

  /// The kinds of finding this scan turned up, for the filter chips.
  List<SecretFindingType> get typesFound {
    final found = {
      for (final project in _projects)
        for (final finding in project.findings) finding.type,
    };
    return SecretFindingType.values.where(found.contains).toList();
  }

  int countOfType(SecretFindingType type) => _projects.fold(
    0,
    (sum, project) =>
        sum + project.findings.where((finding) => finding.type == type).length,
  );

  /// Scans [root] and adds what it finds. A folder scanned again replaces
  /// its earlier results.
  Future<void> scan(String root) async {
    if (_stage == SafeScanStage.scanning) return;
    _error = '';
    _stage = SafeScanStage.scanning;
    _progress = null;
    notifyListeners();
    try {
      final job = _runner(
        root,
        onProgress: (progress) {
          _progress = progress;
          notifyListeners();
        },
      );
      _job = job;
      final result = await job.result;
      if (result != null) _merge(result);
    } catch (error) {
      _error = 'Không dò được $root: $error';
    } finally {
      _job = null;
      _stage = _projects.isEmpty && _roots.isEmpty
          ? SafeScanStage.idle
          : SafeScanStage.done;
      notifyListeners();
    }
  }

  void cancel() => _job?.cancel();

  void _merge(SecretScanResult result) {
    if (!_roots.contains(result.root)) _roots.add(result.root);
    for (final project in result.projects) {
      final index = _projects.indexWhere((x) => x.root == project.root);
      if (index >= 0) {
        _selected.removeWhere((key) => key.startsWith('${project.root}\u0000'));
        _projects[index] = project;
      } else {
        _projects.add(project);
      }
      for (final finding in project.findings) {
        if (!isKnown(finding)) _selected.add(_key(project, finding));
      }
    }
    _disambiguateNames();
    _projects.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    _tooLarge.addAll(result.tooLarge);
    _truncated = _truncated || result.truncated;
  }

  /// Projects from different roots can share a folder name.
  void _disambiguateNames() {
    final seen = <String, int>{};
    for (final project in _projects) {
      seen[project.name] = (seen[project.name] ?? 0) + 1;
    }
    for (final project in _projects) {
      if ((seen[project.name] ?? 0) > 1 && !project.name.endsWith(')')) {
        final parent = project.root
            .split(RegExp(r'[\\/]'))
            .where((part) => part.isNotEmpty)
            .toList();
        if (parent.length >= 2) {
          project.name = '${project.name} (${parent[parent.length - 2]})';
        }
      }
    }
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  void toggleType(SecretFindingType type) {
    if (!_hiddenTypes.remove(type)) _hiddenTypes.add(type);
    notifyListeners();
  }

  void toggleCollapsed(SecretProject project) {
    if (!_collapsed.remove(project.root)) _collapsed.add(project.root);
    notifyListeners();
  }

  /// The findings of [project] the filters let through.
  List<SecretFinding> visibleFindings(SecretProject project) {
    final words = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final projectName = project.name.toLowerCase();
    return project.findings.where((finding) {
      if (_hiddenTypes.contains(finding.type)) return false;
      if (words.isEmpty) return true;
      final haystack = [
        projectName,
        finding.relativePath.toLowerCase(),
        finding.label.toLowerCase(),
        finding.type.label.toLowerCase(),
      ].join(' ');
      return words.every(haystack.contains);
    }).toList();
  }

  List<SecretProject> get visibleProjects => _projects
      .where((project) => visibleFindings(project).isNotEmpty)
      .toList();

  Iterable<SecretFinding> _selectable(SecretProject project) =>
      visibleFindings(project).where((finding) => !isKnown(finding));

  /// True with every visible finding ticked, false with none, null between.
  bool? projectState(SecretProject project) {
    final selectable = _selectable(project).toList();
    if (selectable.isEmpty) return false;
    final ticked = selectable.where((f) => isSelected(project, f)).length;
    if (ticked == 0) return false;
    return ticked == selectable.length ? true : null;
  }

  void toggleFinding(SecretProject project, SecretFinding finding) {
    if (isKnown(finding)) return;
    final key = _key(project, finding);
    if (!_selected.remove(key)) _selected.add(key);
    notifyListeners();
  }

  void toggleProject(SecretProject project) {
    final tickAll = projectState(project) != true;
    for (final finding in _selectable(project)) {
      final key = _key(project, finding);
      if (tickAll) {
        _selected.add(key);
      } else {
        _selected.remove(key);
      }
    }
    notifyListeners();
  }

  void selectAll(bool value) {
    for (final project in visibleProjects) {
      for (final finding in _selectable(project)) {
        final key = _key(project, finding);
        if (value) {
          _selected.add(key);
        } else {
          _selected.remove(key);
        }
      }
    }
    notifyListeners();
  }

  int selectedIn(SecretProject project) =>
      project.findings.where((f) => isSelected(project, f)).length;

  /// Ticked findings, hidden ones included: a filter only narrows the view.
  int get selectedCount => _selected.length;

  int get selectedProjectCount =>
      _projects.where((project) => selectedIn(project) > 0).length;

  int get findingCount =>
      _projects.fold(0, (sum, project) => sum + project.findings.length);

  /// Reads every ticked finding and puts it in the safe with one write.
  Future<SafeScanImport> importSelected() async {
    _importing = true;
    notifyListeners();
    final items = <SafeItem>[];
    final failed = <String>[];
    final projects = <String>{};
    try {
      for (final project in _projects) {
        for (final finding in project.findings) {
          if (!isSelected(project, finding)) continue;
          try {
            items.add(await _itemFor(project, finding));
            projects.add(project.name);
          } catch (_) {
            failed.add(finding.path);
          }
        }
      }
      final saved = await safe.putAll(items);
      if (!saved) {
        throw StateError(safe.error.isEmpty ? 'Không lưu được.' : safe.error);
      }
      for (final project in _projects) {
        for (final finding in project.findings) {
          if (isSelected(project, finding)) _known.add(finding.fingerprint);
        }
      }
      _selected.clear();
      return SafeScanImport(
        imported: items.length,
        projects: projects.length,
        failed: failed,
      );
    } finally {
      _importing = false;
      notifyListeners();
    }
  }

  /// A file's own name reads best on a box; the path inside the project is
  /// kept only when two files of the project share that name (an app's
  /// `.env` beside a backend's `.env`).
  static String _titleFor(SecretProject project, SecretFinding finding) {
    if (finding.type == SecretFindingType.inlineToken) return finding.title;
    final sameName = project.findings.where(
      (other) =>
          other.type != SecretFindingType.inlineToken &&
          other.fileName == finding.fileName,
    );
    return sameName.length > 1 ? finding.relativePath : finding.fileName;
  }

  Future<SafeItem> _itemFor(
    SecretProject project,
    SecretFinding finding,
  ) async {
    final type = finding.type;
    final base = safe
        .draft(type.kind)
        .copyWith(
          title: _titleFor(project, finding),
          project: project.name,
          source: finding.location,
          fileName: type == SecretFindingType.inlineToken
              ? ''
              : finding.fileName,
        );
    if (type == SecretFindingType.inlineToken) {
      final elsewhere = finding.otherPlaces > 0
          ? ' và ${finding.otherPlaces} tệp khác'
          : '';
      return base.copyWith(
        secret: finding.value ?? '',
        notes:
            'Tìm thấy trong ${finding.relativePath} dòng ${finding.line}$elsewhere.',
      );
    }
    final bytes = await _readFile(finding.path);
    if (bytes.length > SafeSecretScanner.maxSecretBytes) {
      throw StateError('too large');
    }
    if (type.isBinary) return base.copyWith(secret: base64Encode(bytes));
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }
    return base.copyWith(secret: text);
  }

  @override
  void dispose() {
    _job?.cancel();
    super.dispose();
  }
}
