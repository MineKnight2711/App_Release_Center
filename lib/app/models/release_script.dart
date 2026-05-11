import 'package:path/path.dart' as p;

enum ReleaseScriptKind {
  release,
  versionCode,
  versionName,
  commit,
  merge,
  deploy,
  imageValidation,
  shell,
  dartTool,
}

class ReleaseScript {
  const ReleaseScript({required this.path, required this.kind});

  final String path;
  final ReleaseScriptKind kind;

  String get fileName => p.basename(path);
  String get extension => p.extension(path).toLowerCase();
  bool get isShellScript => extension == '.sh';
  bool get isDartTool => extension == '.dart';

  String get label {
    return switch (kind) {
      ReleaseScriptKind.release => 'Release flow',
      ReleaseScriptKind.versionCode => 'Version code',
      ReleaseScriptKind.versionName => 'Version name',
      ReleaseScriptKind.commit => 'Commit',
      ReleaseScriptKind.merge => 'Merge PR',
      ReleaseScriptKind.deploy => 'Deploy',
      ReleaseScriptKind.imageValidation => 'Play images',
      ReleaseScriptKind.shell => _humanize(fileName),
      ReleaseScriptKind.dartTool => _humanize(fileName),
    };
  }

  String get description {
    return switch (kind) {
      ReleaseScriptKind.release => 'Runs version, commit, merge, and deploy.',
      ReleaseScriptKind.versionCode => 'Updates the Android build number.',
      ReleaseScriptKind.versionName => 'Updates the release version name.',
      ReleaseScriptKind.commit => 'Commits and pushes release changes.',
      ReleaseScriptKind.merge => 'Creates and waits for the dev pull request.',
      ReleaseScriptKind.deploy => 'Runs deployment options for this project.',
      ReleaseScriptKind.imageValidation => 'Checks Google Play image assets.',
      ReleaseScriptKind.shell => 'Runs this shell script.',
      ReleaseScriptKind.dartTool => 'Runs this Dart tool.',
    };
  }

  static String _humanize(String fileName) {
    final name = p.basenameWithoutExtension(fileName);
    return name
        .split(RegExp(r'[_-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
