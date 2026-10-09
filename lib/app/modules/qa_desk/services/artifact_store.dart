import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../models/qa_models.dart';
import 'qa_desk_storage.dart';

class ArtifactStore {
  const ArtifactStore({this.rootOverride});

  final String? rootOverride;

  Future<String> saveLog(SuiteRun run) async {
    final file = File(await artifactPath(run, '${_safe(run.runId)}.log'));
    await file.writeAsString('${run.logs.join('\n')}\n', flush: true);
    return file.path;
  }

  Future<String> saveBytes(
    SuiteRun run,
    String fileName,
    Uint8List bytes,
  ) async {
    final file = File(await artifactPath(run, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String> artifactPath(SuiteRun run, String fileName) async {
    final root = rootOverride ?? await qaDeskRoot();
    final folder = Directory(
      path.join(
        root,
        QaDeskStorage.artifactsName,
        _safe(run.batchId),
        _safe(run.sourceId),
        _safe(run.suiteId),
      ),
    );
    await folder.create(recursive: true);
    return path.join(folder.path, _safe(fileName));
  }
}

String _safe(String value) => value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
