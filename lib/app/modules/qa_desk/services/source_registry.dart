import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/qa_models.dart';
import 'qa_desk_storage.dart';

abstract interface class SourceRegistry {
  Future<List<QaSource>> load();
  Future<void> save(List<QaSource> sources);
}

class FileSourceRegistry implements SourceRegistry {
  const FileSourceRegistry({this.path});

  /// Defaults to `sources.json` in QA Desk's folder.
  final String? path;

  Future<File> _registryFile() async {
    final file = File(
      path ?? p.join(await qaDeskRoot(), QaDeskStorage.sourcesName),
    );
    await file.parent.create(recursive: true);
    return file;
  }

  @override
  Future<List<QaSource>> load() async {
    final file = await _registryFile();
    if (!await file.exists()) return [];

    try {
      return decodeSources(await file.readAsString());
    } on FormatException {
      return [];
    }
  }

  @override
  Future<void> save(List<QaSource> sources) async {
    final file = await _registryFile();
    await file.writeAsString(encodeSources(sources), flush: true);
  }
}

class MemorySourceRegistry implements SourceRegistry {
  MemorySourceRegistry([List<QaSource> initial = const []])
    : _sources = List.of(initial);

  List<QaSource> _sources;

  @override
  Future<List<QaSource>> load() async => List.of(_sources);

  @override
  Future<void> save(List<QaSource> sources) async {
    _sources = List.of(sources);
  }
}
