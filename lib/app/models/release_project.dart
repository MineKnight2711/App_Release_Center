import 'dart:io';

import 'package:app_release_center/app/models/release_script.dart';
import 'package:path/path.dart' as p;

class ReleaseProject {
  const ReleaseProject({
    required this.path,
    required this.scripts,
    required this.hasPlayReleaseTools,
    this.pubspecVersion,
  });

  final String path;
  final List<ReleaseScript> scripts;
  final bool hasPlayReleaseTools;
  final String? pubspecVersion;

  String get name => p.basename(path);
  Directory get directory => Directory(path);
  Directory get autoDirectory => Directory(p.join(path, 'auto'));

  ReleaseScript? get imageValidator {
    return scriptByName('check_play_images.dart');
  }

  ReleaseScript? scriptByName(String fileName) {
    for (final script in scripts) {
      if (script.fileName == fileName) return script;
    }
    return null;
  }
}
