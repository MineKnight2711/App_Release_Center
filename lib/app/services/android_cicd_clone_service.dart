import 'dart:io';

import 'package:app_release_center/app/services/ch_play_project_inspector_service.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

enum AndroidCicdFileAction { add, overwrite, skip }

enum AndroidCicdCloneMode { adaptive, fallback }

class AndroidCicdFileChange {
  const AndroidCicdFileChange({
    required this.relativePath,
    required this.action,
  });

  final String relativePath;
  final AndroidCicdFileAction action;
}

class AndroidCicdClonePreview {
  const AndroidCicdClonePreview({
    required this.projectPath,
    required this.applicationId,
    required this.flavors,
    required this.selectedFlavor,
    required this.gradleFilePath,
    required this.mode,
    required this.changes,
    required this.warnings,
    required this.drafts,
  });

  final String projectPath;
  final String? applicationId;
  final List<String> flavors;
  final String? selectedFlavor;
  final String gradleFilePath;
  final AndroidCicdCloneMode mode;
  final List<AndroidCicdFileChange> changes;
  final List<String> warnings;
  final List<AndroidCicdFileDraft> drafts;

  bool get hasFlavors => flavors.isNotEmpty;
  bool get isFallback => mode == AndroidCicdCloneMode.fallback;

  int count(AndroidCicdFileAction action) {
    return changes.where((change) => change.action == action).length;
  }

  AndroidCicdFileChange? changeFor(String relativePath) {
    final normalized = _normalizeRelativePath(relativePath);
    for (final change in changes) {
      if (change.relativePath == normalized) return change;
    }
    return null;
  }
}

class AndroidCicdCloneResult {
  const AndroidCicdCloneResult({
    required this.preview,
    required this.writtenFiles,
    required this.skippedFiles,
  });

  final AndroidCicdClonePreview preview;
  final List<String> writtenFiles;
  final List<String> skippedFiles;
}

class AndroidCicdFileDraft {
  const AndroidCicdFileDraft({
    required this.relativePath,
    required this.content,
  });

  final String relativePath;
  final String content;
}

class AndroidCicdCloneService extends GetxService {
  Future<AndroidCicdClonePreview> preview(
    String projectPath, {
    bool overwriteExisting = true,
    AndroidCicdCloneMode mode = AndroidCicdCloneMode.adaptive,
  }) async {
    final root = Directory(p.normalize(projectPath));
    if (!root.existsSync()) {
      throw FileSystemException('Project directory does not exist.', root.path);
    }

    final pubspec = File(p.join(root.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw FileSystemException(
        'Selected directory is not a Flutter project.',
        root.path,
      );
    }

    final androidDirectory = Directory(p.join(root.path, 'android'));
    if (!androidDirectory.existsSync()) {
      throw FileSystemException(
        'Selected Flutter project does not contain an android folder.',
        root.path,
      );
    }

    final isFallback = mode == AndroidCicdCloneMode.fallback;
    final gradleFile = _findAppGradleFile(root.path);
    if (gradleFile == null && !isFallback) {
      throw FileSystemException(
        'Could not find android/app/build.gradle or build.gradle.kts.',
        root.path,
      );
    }

    final gradleSource = gradleFile == null
        ? ''
        : await gradleFile.readAsString();
    final applicationId = gradleSource.isEmpty
        ? null
        : ChPlayProjectInspectorService.parseApplicationId(gradleSource);
    final packageName = applicationId ?? 'com.example.app';
    final detectedFlavors = gradleSource.isEmpty
        ? <String>[]
        : parseProductFlavors(gradleSource);
    final flavors = isFallback ? <String>[] : detectedFlavors;
    final selectedFlavor = isFallback ? null : selectDefaultFlavor(flavors);
    final warnings = <String>[];

    if (isFallback) {
      warnings.add(
        'Fallback mode uses a no-flavor Fastfile and skips Gradle signing patching.',
      );
      if (detectedFlavors.isNotEmpty) {
        warnings.add(
          'Detected flavors were ignored: ${detectedFlavors.join(', ')}. Set ANDROID_FLAVOR manually if this app requires one.',
        );
      }
      if (gradleFile == null) {
        warnings.add(
          'Gradle app build file was not found. Update ANDROID_PACKAGE_NAME before uploading.',
        );
      }
    }

    final drafts = <AndroidCicdFileDraft>[
      AndroidCicdFileDraft(
        relativePath: 'android/fastlane/Fastfile',
        content: _fastfile(
          applicationId: packageName,
          selectedFlavor: selectedFlavor,
        ),
      ),
      AndroidCicdFileDraft(
        relativePath: 'android/env.properties.example',
        content: _envPropertiesExample(
          applicationId: packageName,
          selectedFlavor: selectedFlavor,
        ),
      ),
      const AndroidCicdFileDraft(
        relativePath: 'android/fastlane/keys/.gitignore',
        content: _fastlaneKeysGitignore,
      ),
      const AndroidCicdFileDraft(
        relativePath: 'android/fastlane/keys/.gitkeep',
        content: '',
      ),
      const AndroidCicdFileDraft(
        relativePath:
            'android/fastlane/metadata/android/vi/changelogs/default.txt',
        content: 'Bug fixes and performance improvements.\n',
      ),
      const AndroidCicdFileDraft(
        relativePath: 'android/fastlane/metadata/android/vi/images/.gitignore',
        content: _playImagesGitignore,
      ),
      const AndroidCicdFileDraft(
        relativePath: 'android/fastlane/metadata/android/vi/images/README.md',
        content: _playImagesReadme,
      ),
      const AndroidCicdFileDraft(
        relativePath:
            'android/fastlane/metadata/android/vi/images/icon/.gitkeep',
        content: '',
      ),
      const AndroidCicdFileDraft(
        relativePath:
            'android/fastlane/metadata/android/vi/images/featureGraphic/.gitkeep',
        content: '',
      ),
      const AndroidCicdFileDraft(
        relativePath:
            'android/fastlane/metadata/android/vi/images/phoneScreenshots/.gitkeep',
        content: '',
      ),
      const AndroidCicdFileDraft(
        relativePath:
            'android/fastlane/metadata/android/vi/images/sevenInchScreenshots/.gitkeep',
        content: '',
      ),
      const AndroidCicdFileDraft(
        relativePath: 'auto/release.sh',
        content: _releaseScript,
      ),
      const AndroidCicdFileDraft(
        relativePath: 'auto/all.sh',
        content: _allScript,
      ),
      const AndroidCicdFileDraft(
        relativePath: 'auto/bump_ver_code.sh',
        content: _bumpVersionCodeScript,
      ),
      const AndroidCicdFileDraft(
        relativePath: 'auto/control_ver_code.sh',
        content: _controlVersionCodeScript,
      ),
      const AndroidCicdFileDraft(
        relativePath: 'auto/control_ver_name.sh',
        content: _controlVersionNameScript,
      ),
      const AndroidCicdFileDraft(
        relativePath: 'auto/commit.sh',
        content: _commitScript,
      ),
      const AndroidCicdFileDraft(
        relativePath: 'auto/merge.sh',
        content: _mergeScript,
      ),
      const AndroidCicdFileDraft(
        relativePath: 'auto/deploy.sh',
        content: _deployScript,
      ),
      const AndroidCicdFileDraft(
        relativePath: 'auto/check_play_images.dart',
        content: _playImagesValidator,
      ),
    ];

    final androidGitignore = _androidGitignoreDraft(root.path);
    if (androidGitignore != null) drafts.add(androidGitignore);

    if (!isFallback && gradleFile != null) {
      final gradleDraft = _gradleSigningDraft(
        rootPath: root.path,
        gradleFile: gradleFile,
        source: gradleSource,
        warnings: warnings,
      );
      if (gradleDraft != null) drafts.add(gradleDraft);
    }

    if (applicationId == null) {
      warnings.add(
        'Application id was not detected. The scaffold will use com.example.app; update ANDROID_PACKAGE_NAME in android/env.properties before uploading.',
      );
    }

    final changes = drafts.map((draft) {
      final file = _targetFile(root.path, draft.relativePath);
      final exists = file.existsSync();
      final sameContent = exists && file.readAsStringSync() == draft.content;
      final action = sameContent || (exists && !overwriteExisting)
          ? AndroidCicdFileAction.skip
          : exists
          ? AndroidCicdFileAction.overwrite
          : AndroidCicdFileAction.add;

      return AndroidCicdFileChange(
        relativePath: draft.relativePath,
        action: action,
      );
    }).toList();

    return AndroidCicdClonePreview(
      projectPath: root.path,
      applicationId: applicationId,
      flavors: flavors,
      selectedFlavor: selectedFlavor,
      gradleFilePath: gradleFile == null
          ? 'Not found'
          : p.relative(gradleFile.path, from: root.path),
      mode: mode,
      changes: changes,
      warnings: warnings,
      drafts: drafts,
    );
  }

  Future<AndroidCicdCloneResult> apply(AndroidCicdClonePreview preview) async {
    final writtenFiles = <String>[];
    final skippedFiles = <String>[];

    for (final draft in preview.drafts) {
      final change = preview.changeFor(draft.relativePath);
      if (change?.action == AndroidCicdFileAction.skip) {
        skippedFiles.add(draft.relativePath);
        continue;
      }

      final file = _targetFile(preview.projectPath, draft.relativePath);
      file.parent.createSync(recursive: true);
      await file.writeAsString(draft.content);
      writtenFiles.add(draft.relativePath);
    }

    return AndroidCicdCloneResult(
      preview: preview,
      writtenFiles: writtenFiles,
      skippedFiles: skippedFiles,
    );
  }

  static List<String> parseProductFlavors(String source) {
    final block = _extractBlock(source, 'productFlavors');
    if (block == null) return const [];

    final names = <String>[];
    final seen = <String>{};

    void addName(String? raw) {
      final name = raw?.trim();
      if (name == null || name.isEmpty) return;
      if (_reservedGradleBlocks.contains(name)) return;
      if (seen.add(name)) names.add(name);
    }

    for (final match in RegExp(
      r'''create\s*\(\s*["']([A-Za-z0-9_]+)["']\s*\)\s*\{''',
    ).allMatches(block)) {
      addName(match.group(1));
    }

    for (final match in RegExp(
      r'''^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\{''',
      multiLine: true,
    ).allMatches(block)) {
      addName(match.group(1));
    }

    return names;
  }

  static String? selectDefaultFlavor(List<String> flavors) {
    if (flavors.isEmpty) return null;
    for (final flavor in flavors) {
      if (flavor.toLowerCase() == 'production') return flavor;
    }
    return flavors.first;
  }

  File? _findAppGradleFile(String rootPath) {
    final candidates = [
      File(p.join(rootPath, 'android', 'app', 'build.gradle')),
      File(p.join(rootPath, 'android', 'app', 'build.gradle.kts')),
    ];
    for (final file in candidates) {
      if (file.existsSync()) return file;
    }
    return null;
  }

  AndroidCicdFileDraft? _androidGitignoreDraft(String rootPath) {
    final file = File(p.join(rootPath, 'android', '.gitignore'));
    final existing = file.existsSync() ? file.readAsStringSync() : '';
    final lines = existing.split(RegExp(r'\r?\n'));
    final existingEntries = lines.map((line) => line.trim()).toSet();
    final missingEntries = const [
      '/env.properties',
      '/key.properties',
    ].where((entry) => !existingEntries.contains(entry)).toList();
    if (missingEntries.isEmpty) return null;

    final separator = existing.isEmpty || existing.endsWith('\n') ? '' : '\n';
    return AndroidCicdFileDraft(
      relativePath: 'android/.gitignore',
      content: '$existing$separator${missingEntries.join('\n')}\n',
    );
  }

  AndroidCicdFileDraft? _gradleSigningDraft({
    required String rootPath,
    required File gradleFile,
    required String source,
    required List<String> warnings,
  }) {
    if (source.contains('env.properties') ||
        source.contains('ANDROID_JKS_PATH') ||
        source.contains('releaseKeystoreFile')) {
      warnings.add('Gradle signing already appears to use env.properties.');
      return null;
    }

    final isKotlin = gradleFile.path.endsWith('.kts');
    final patched = isKotlin
        ? _patchKotlinGradle(source, warnings)
        : _patchGroovyGradle(source, warnings);
    if (patched == null || patched == source) return null;

    return AndroidCicdFileDraft(
      relativePath: _normalizeRelativePath(
        p.relative(gradleFile.path, from: rootPath),
      ),
      content: patched,
    );
  }

  String? _patchGroovyGradle(String source, List<String> warnings) {
    if (source.contains(RegExp(r'^\s*signingConfigs\s*\{', multiLine: true))) {
      warnings.add(
        'Gradle signingConfigs already exists. Review signing manually before release.',
      );
      return null;
    }
    if (!source.contains(RegExp(r'^\s*android\s*\{', multiLine: true)) ||
        !source.contains(RegExp(r'^\s*buildTypes\s*\{', multiLine: true))) {
      warnings.add(
        'Could not safely patch Groovy Gradle signing. Add android/env.properties signing manually.',
      );
      return null;
    }

    var patched = source.replaceFirst(
      RegExp(r'^android\s*\{', multiLine: true),
      '${_groovySigningPreamble}android {',
    );
    patched = patched.replaceFirstMapped(
      RegExp(r'^(\s*)buildTypes\s*\{', multiLine: true),
      (match) =>
          '${_indent(_groovySigningConfig, match.group(1)!)}\n${match.group(0)!}',
    );

    final debugPattern = RegExp(
      r'^(\s*)signingConfig\s*=?\s*signingConfigs\.debug\s*$',
      multiLine: true,
    );
    if (debugPattern.hasMatch(patched)) {
      patched = patched.replaceFirstMapped(
        debugPattern,
        (match) => _indent(_groovyReleaseSigningChoice, match.group(1)!),
      );
    } else {
      final releasePattern = RegExp(r'^(\s*)release\s*\{\s*$', multiLine: true);
      if (!releasePattern.hasMatch(patched)) {
        warnings.add(
          'Could not find release build type to attach env.properties signing.',
        );
        return patched;
      }
      patched = patched.replaceFirstMapped(
        releasePattern,
        (match) =>
            '${match.group(0)!}\n${_indent(_groovyReleaseSigningChoice, '${match.group(1)!}    ')}',
      );
    }

    return patched;
  }

  String? _patchKotlinGradle(String source, List<String> warnings) {
    if (source.contains(RegExp(r'^\s*signingConfigs\s*\{', multiLine: true))) {
      warnings.add(
        'Gradle signingConfigs already exists. Review signing manually before release.',
      );
      return null;
    }
    if (!source.contains(RegExp(r'^\s*android\s*\{', multiLine: true)) ||
        !source.contains(RegExp(r'^\s*buildTypes\s*\{', multiLine: true))) {
      warnings.add(
        'Could not safely patch Kotlin Gradle signing. Add android/env.properties signing manually.',
      );
      return null;
    }

    var patched = source;
    final missingImports = [
      if (!patched.contains('import java.io.File')) 'import java.io.File',
      if (!patched.contains('import java.util.Properties'))
        'import java.util.Properties',
    ];
    if (missingImports.isNotEmpty) {
      patched = '${missingImports.join('\n')}\n\n$patched';
    }
    patched = patched.replaceFirst(
      RegExp(r'^android\s*\{', multiLine: true),
      '${_kotlinSigningPreamble}android {',
    );
    patched = patched.replaceFirstMapped(
      RegExp(r'^(\s*)buildTypes\s*\{', multiLine: true),
      (match) =>
          '${_indent(_kotlinSigningConfig, match.group(1)!)}\n${match.group(0)!}',
    );

    final debugPattern = RegExp(
      r'''^(\s*)signingConfig\s*=\s*signingConfigs\.getByName\(["']debug["']\)\s*$''',
      multiLine: true,
    );
    if (debugPattern.hasMatch(patched)) {
      patched = patched.replaceFirstMapped(
        debugPattern,
        (match) => _indent(_kotlinReleaseSigningChoice, match.group(1)!),
      );
    } else {
      final releasePattern = RegExp(r'^(\s*)release\s*\{\s*$', multiLine: true);
      if (!releasePattern.hasMatch(patched)) {
        warnings.add(
          'Could not find release build type to attach env.properties signing.',
        );
        return patched;
      }
      patched = patched.replaceFirstMapped(
        releasePattern,
        (match) =>
            '${match.group(0)!}\n${_indent(_kotlinReleaseSigningChoice, '${match.group(1)!}    ')}',
      );
    }

    return patched;
  }

  static String _fastfile({
    required String applicationId,
    required String? selectedFlavor,
  }) {
    final defaultFlavor = selectedFlavor == null ? 'nil' : '"$selectedFlavor"';
    return _fastlaneTemplate
        .replaceAll('__ANDROID_PACKAGE_NAME__', applicationId)
        .replaceAll('__DEFAULT_ANDROID_FLAVOR__', defaultFlavor);
  }

  static String _envPropertiesExample({
    required String applicationId,
    required String? selectedFlavor,
  }) {
    return '''
# Android/Fastlane release config.
# Copy this file to android/env.properties and fill in local secret values.
KEY_ALIAS=release
ANDROID_JKS_PATH=fastlane/keys/release.jks
STORE_PASSWORD=change-me
KEY_PASSWORD=change-me
FASTLANE_KEY_PATH=fastlane/keys/google-play-service-account.json
ANDROID_PACKAGE_NAME=$applicationId
PLAY_TRACK=production
ANDROID_FLAVOR=${selectedFlavor ?? ''}
''';
  }

  static File _targetFile(String rootPath, String relativePath) {
    return File(p.joinAll([rootPath, ...relativePath.split('/')]));
  }

  static String? _extractBlock(String source, String blockName) {
    final blockMatch = RegExp('\\b$blockName\\s*\\{').firstMatch(source);
    if (blockMatch == null) return null;

    final openBraceIndex = source.indexOf('{', blockMatch.start);
    if (openBraceIndex < 0) return null;

    var depth = 0;
    for (var i = openBraceIndex; i < source.length; i++) {
      final char = source[i];
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          return source.substring(openBraceIndex + 1, i);
        }
      }
    }

    return source.substring(openBraceIndex + 1);
  }

  static String _indent(String source, String prefix) {
    return source
        .trimRight()
        .split('\n')
        .map((line) => line.isEmpty ? line : '$prefix$line')
        .join('\n');
  }
}

String _normalizeRelativePath(String path) {
  return path.replaceAll('\\', '/');
}

const _reservedGradleBlocks = {
  'applicationId',
  'buildConfigField',
  'dimension',
  'externalNativeBuild',
  'manifestPlaceholders',
  'ndk',
  'resValue',
  'signingConfig',
};

const _groovySigningPreamble = r'''
def envProperties = new Properties()
def envFile = rootProject.file("env.properties")
if (envFile.exists()) {
    envFile.withInputStream { stream ->
        envProperties.load(stream)
    }
}

def nullIfBlank = { value ->
    def trimmed = value == null ? null : value.toString().trim()
    trimmed ? trimmed : null
}

def resolveKeystoreFile = { rawPath ->
    def path = nullIfBlank(rawPath)
    if (path == null) {
        return null
    }

    if (path.startsWith("~")) {
        path = path.replaceFirst("~", System.getProperty("user.home"))
    }

    def candidate = new File(path)
    candidate.isAbsolute() ? candidate : rootProject.file(path)
}

def releaseKeystoreFile = resolveKeystoreFile(envProperties.getProperty("ANDROID_JKS_PATH"))
if (releaseKeystoreFile != null && !releaseKeystoreFile.exists()) {
    releaseKeystoreFile = null
}
def releaseKeyAlias = nullIfBlank(envProperties.getProperty("KEY_ALIAS"))
def releaseStorePassword = nullIfBlank(envProperties.getProperty("STORE_PASSWORD"))
def releaseKeyPassword = nullIfBlank(envProperties.getProperty("KEY_PASSWORD")) ?: releaseStorePassword

''';

const _groovySigningConfig = r'''
signingConfigs {
    release {
        enableV1Signing true
        enableV2Signing true

        keyAlias releaseKeyAlias ?: ""
        keyPassword releaseKeyPassword ?: ""
        storePassword releaseStorePassword ?: ""

        if (releaseKeystoreFile != null) {
            storeFile releaseKeystoreFile
        }
    }
}
''';

const _groovyReleaseSigningChoice = r'''
if (releaseKeystoreFile != null && releaseKeyAlias != null && releaseStorePassword != null) {
    signingConfig = signingConfigs.release
} else {
    logger.warn("Release keystore is not fully configured in android/env.properties. Using debug signing config for release build.")
    signingConfig = signingConfigs.debug
}
''';

const _kotlinSigningPreamble = r'''
val envProperties = Properties()
val envFile = rootProject.file("env.properties")
if (envFile.exists()) {
    envFile.inputStream().use { envProperties.load(it) }
}

fun nullIfBlank(value: String?): String? {
    val trimmed = value?.trim()
    return if (trimmed.isNullOrEmpty()) null else trimmed
}

fun resolveKeystoreFile(rawPath: String?): File? {
    var path = nullIfBlank(rawPath) ?: return null
    if (path.startsWith("~")) {
        path = path.replaceFirst("~", System.getProperty("user.home"))
    }

    val candidate = File(path)
    return if (candidate.isAbsolute) candidate else rootProject.file(path)
}

val releaseKeystoreFile = resolveKeystoreFile(envProperties.getProperty("ANDROID_JKS_PATH"))
    ?.takeIf { it.exists() }
val releaseKeyAlias = nullIfBlank(envProperties.getProperty("KEY_ALIAS"))
val releaseStorePassword = nullIfBlank(envProperties.getProperty("STORE_PASSWORD"))
val releaseKeyPassword = nullIfBlank(envProperties.getProperty("KEY_PASSWORD")) ?: releaseStorePassword

''';

const _kotlinSigningConfig = r'''
signingConfigs {
    create("release") {
        enableV1Signing = true
        enableV2Signing = true

        keyAlias = releaseKeyAlias ?: ""
        keyPassword = releaseKeyPassword ?: ""
        storePassword = releaseStorePassword ?: ""

        if (releaseKeystoreFile != null) {
            storeFile = releaseKeystoreFile
        }
    }
}
''';

const _kotlinReleaseSigningChoice = r'''
signingConfig = if (
    releaseKeystoreFile != null &&
    releaseKeyAlias != null &&
    releaseStorePassword != null
) {
    signingConfigs.getByName("release")
} else {
    logger.warn("Release keystore is not fully configured in android/env.properties. Using debug signing config for release build.")
    signingConfigs.getByName("debug")
}
''';

const _fastlaneTemplate = r'''
require "dotenv"
require "fileutils"
require "shellwords"

Dotenv.load(File.expand_path("../env.properties", __dir__))

def pubspec_path
  File.expand_path("../../pubspec.yaml", __dir__)
end

def read_pubspec_version
  path = pubspec_path
  UI.user_error!("pubspec.yaml not found at #{path}") unless File.exist?(path)

  content = File.read(path)
  line = content.lines.find { |l| l =~ /^\s*version:\s*\S+/ }
  UI.user_error!("Could not find 'version:' in pubspec.yaml") if line.to_s.strip.empty?

  raw_version = line.sub(/^\s*version:\s*/, "").strip
  match = raw_version.match(/^(?<name>[^\+]+)\+(?<code>\d+)$/)
  UI.user_error!("Invalid pubspec version format '#{raw_version}'. Expected '<version_name>+<version_code>'") unless match

  {
    path: path,
    content: content,
    raw_version: raw_version,
    version_name: match[:name],
    version_code: match[:code].to_i
  }
end

def write_pubspec_version(version_name:, version_code:)
  UI.user_error!("version_code must be > 0") if version_code.to_i <= 0

  info = read_pubspec_version
  updated_line = "version: #{version_name}+#{version_code}"
  updated = false
  updated_content = info[:content].sub(/^\s*version:\s*\S+\s*$/) do
    updated = true
    updated_line
  end

  UI.user_error!("Failed to update pubspec.yaml version line") unless updated

  File.write(info[:path], updated_content)
  UI.success("Updated pubspec.yaml to #{updated_line}")
  puts "PUBSPEC_VERSION_ONLY:#{version_name}+#{version_code}"
end

def resolve_package_name
  package_name = ENV["ANDROID_PACKAGE_NAME"].to_s.strip
  package_name.empty? ? "__ANDROID_PACKAGE_NAME__" : package_name
end

def resolve_track(options)
  (options[:track] || ENV["PLAY_TRACK"] || "production").to_s
end

def resolve_android_flavor(options)
  flavor = (options[:flavor] || ENV["ANDROID_FLAVOR"]).to_s.strip
  flavor.empty? ? __DEFAULT_ANDROID_FLAVOR__ : flavor
end

def resolve_fastlane_key_path!
  json_key = ENV["FASTLANE_KEY_PATH"].to_s.strip
  UI.user_error!("Missing FASTLANE_KEY_PATH in android/env.properties") if json_key.empty?

  android_root = File.expand_path("..", __dir__)
  resolved_path = File.expand_path(json_key, android_root)
  ENV["FASTLANE_KEY_PATH"] = resolved_path

  resolved_path
end

def project_root
  File.expand_path("../..", __dir__)
end

def flutter_build_command(artifact:, flavor:)
  command = "cd #{Shellwords.escape(project_root)} && flutter build #{artifact} --release"
  command += " --flavor #{Shellwords.escape(flavor)}" if flavor
  command
end

def release_aab_path(flavor)
  if flavor
    File.expand_path("build/app/outputs/bundle/#{flavor}Release/app-#{flavor}-release.aab", project_root)
  else
    File.expand_path("build/app/outputs/bundle/release/app-release.aab", project_root)
  end
end

def play_images_validator_path
  File.join(project_root, "auto", "check_play_images.dart")
end

def play_images_dir
  File.join(project_root, "android", "fastlane", "metadata", "android", "vi", "images")
end

def image_extensions
  [".png", ".jpg", ".jpeg"]
end

def env_yes?(key, default: true)
  raw = ENV[key].to_s.strip.downcase
  return default if raw.empty?

  ["1", "true", "yes", "y"].include?(raw)
end

def stage_named_image_from_folder(base_name)
  folder = File.join(play_images_dir, base_name)
  return unless Dir.exist?(folder)

  folder_images = Dir.children(folder)
                     .map { |name| File.join(folder, name) }
                     .select { |path| File.file?(path) && image_extensions.include?(File.extname(path).downcase) }
  root_images = image_extensions
                  .map { |ext| File.join(play_images_dir, "#{base_name}#{ext}") }
                  .select { |path| File.file?(path) }

  return unless folder_images.size == 1

  source = folder_images.first
  root_images.each { |path| FileUtils.rm_f(path) }
  destination = File.join(play_images_dir, "#{base_name}#{File.extname(source).downcase}")
  FileUtils.cp(source, destination)
  UI.message("Staged #{base_name} image for Fastlane upload: #{destination}")
end

default_platform(:android)

platform :android do
  lane :fetch_version_code_from_play_store do |options|
    track = resolve_track(options)
    json_key = resolve_fastlane_key_path!
    package_name = resolve_package_name

    UI.message("Using JSON key from: #{json_key}")
    UI.message("Fetching version code on track '#{track}' for package '#{package_name}'")

    codes = google_play_track_version_codes(
      package_name: package_name,
      track: track,
      json_key: json_key
    )

    latest = codes.map(&:to_i).max || 0
    UI.success("Current version code on track '#{track}': #{latest}")
    puts "STORE_CODE_ONLY:#{latest}"
    latest
  end

  lane :get_local_version_code do
    local = read_pubspec_version[:version_code]
    UI.success("Local project version code (pubspec.yaml): #{local}")
    puts "LOCAL_CODE_ONLY:#{local}"
    local
  end

  lane :compare_version_codes do |options|
    track = resolve_track(options)
    store_code = fetch_version_code_from_play_store(track: track).to_i
    local_code = get_local_version_code.to_i

    if local_code < store_code
      UI.important("Local code (#{local_code}) is BEHIND Play Store (#{store_code})")
    elsif local_code > store_code
      UI.important("Local code (#{local_code}) is AHEAD of Play Store (#{store_code})")
    else
      UI.success("Local code is UP-TO-DATE (#{local_code})")
    end
  end

  lane :bump_version_code do |options|
    track = resolve_track(options)
    new_code = fetch_version_code_from_play_store(track: track).to_i + 1
    UI.message("Bumping version code to #{new_code}")
    set_version_code(version_code: new_code)
  end

  lane :set_version_code do |options|
    new_code = options[:version_code].to_i
    UI.user_error!("version_code must be > 0") if new_code <= 0
    current = read_pubspec_version
    write_pubspec_version(version_name: current[:version_name], version_code: new_code)
  end

  desc "Get the version name of the current project"
  lane :get_version_name do
    version_name = read_pubspec_version[:version_name]
    UI.success("Current Version Name: #{version_name}")
    puts "Current Version Name: #{version_name}"
    puts "VERSION_NAME_ONLY:#{version_name}"
  end

  desc "Manually update version name"
  lane :update_version_name do |options|
    new_version_name = options[:version_name].to_s.strip
    UI.user_error!("You must provide a new version name using the 'version_name:' parameter.") if new_version_name.empty?
    UI.user_error!("Invalid version name. '+' is not allowed in version_name.") if new_version_name.include?("+")

    UI.message("Updating version name to: #{new_version_name}")
    current = read_pubspec_version
    write_pubspec_version(version_name: new_version_name, version_code: current[:version_code])
  end

  desc "Build the release AAB without uploading it"
  lane :build_aab do |options|
    flavor = resolve_android_flavor(options)
    sh(flutter_build_command(artifact: "appbundle", flavor: flavor))

    aab_path = release_aab_path(flavor)
    UI.message("Checking AAB at: #{aab_path}")
    UI.user_error!("AAB not found at #{aab_path}") unless File.exist?(aab_path)
    UI.success("AAB built: #{aab_path}")
    puts "ARC_AAB_PATH:#{aab_path}"
    aab_path
  end

  desc "Upload the AAB to Google Play"
  lane :upload_to_chplay do |options|
    update_description = (options[:update_description] || ENV["UPDATE_DESCRIPTION"]).to_s.strip
    upload_play_images = env_yes?("UPLOAD_PLAY_IMAGES", default: true)

    track = resolve_track(options)
    flavor = resolve_android_flavor(options)
    json_key = resolve_fastlane_key_path!
    package_name = resolve_package_name

    changelog_locale = "vi"
    metadata_root = File.expand_path("metadata/android", __dir__)
    changelog_dir = File.join(metadata_root, changelog_locale, "changelogs")
    FileUtils.mkdir_p(changelog_dir)

    version_code = read_pubspec_version[:version_code]
    default_changelog = File.join(changelog_dir, "default.txt")
    versioned_changelog = File.join(changelog_dir, "#{version_code}.txt")

    if update_description.empty?
      has_versioned_changelog = File.exist?(versioned_changelog) && !File.read(versioned_changelog).strip.empty?
      has_default_changelog = File.exist?(default_changelog) && !File.read(default_changelog).strip.empty?

      unless has_versioned_changelog || has_default_changelog
        UI.user_error!(
          "Missing update_description and no changelog found. " \
          "Pass update_description or create #{versioned_changelog} (or #{default_changelog})."
        )
      end

      if has_versioned_changelog
        UI.message("Using existing changelog file: #{versioned_changelog}")
      else
        UI.message("Using fallback changelog file: #{default_changelog}")
      end
    else
      File.write(default_changelog, update_description)
      File.write(versioned_changelog, update_description)
      UI.message("Prepared changelogs for locale '#{changelog_locale}' and version code #{version_code}")
    end

    if upload_play_images
      sh("dart #{Shellwords.escape(play_images_validator_path)}") unless ENV["SKIP_PLAY_IMAGE_CHECK"] == "1"
      stage_named_image_from_folder("icon")
      stage_named_image_from_folder("featureGraphic")
    else
      UI.message("Skipping Google Play listing images/app icon/screenshots upload.")
    end

    skip_build_raw = (options[:skip_build] || ENV["SKIP_PLAY_BUILD"]).to_s.strip.downcase
    skip_build = ["1", "true", "yes", "y"].include?(skip_build_raw)
    if skip_build
      UI.message("Using the existing AAB from the separate build step.")
    else
      build_aab(options)
    end

    aab_path = release_aab_path(flavor)
    UI.message("Checking AAB at: #{aab_path}")
    UI.user_error!("AAB not found at #{aab_path}") unless File.exist?(aab_path)
    puts "ARC_AAB_PATH:#{aab_path}"

    supply(
      track: track,
      package_name: package_name,
      aab: aab_path,
      json_key: json_key,
      metadata_path: metadata_root,
      skip_upload_changelogs: false,
      skip_upload_metadata: true,
      skip_upload_images: !upload_play_images,
      skip_upload_screenshots: !upload_play_images
    )
  end
end
''';

const _fastlaneKeysGitignore = '''
*.json
*.jks
*.keystore
!.gitkeep
''';

const _playImagesGitignore = '''
/icon.png
/icon.jpg
/icon.jpeg
/featureGraphic.png
/featureGraphic.jpg
/featureGraphic.jpeg
''';

const _playImagesReadme = r'''
# Google Play Image Uploads

Place Google Play listing images in this folder using Fastlane's expected names.

## Upload Locations

- App logo: put one PNG/JPEG in `icon/`
- Featured image: put one PNG/JPEG in `featureGraphic/`
- Phone screenshots: `phoneScreenshots/`
- 7-inch tablet screenshots: `sevenInchScreenshots/`

Fastlane uploads the app logo from `icon.png`, `icon.jpg`, or `icon.jpeg` in this folder. The deploy lane stages the image from `icon/` into that required filename automatically.

Fastlane uploads the featured image from `featureGraphic.png`, `featureGraphic.jpg`, or `featureGraphic.jpeg` in this folder. The deploy lane stages the image from `featureGraphic/` into that required filename automatically.

Run this before deploying:

```sh
dart auto/check_play_images.dart
```
''';

const _releaseScript = r'''#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$SCRIPT_DIR"

echo "Starting the release process..."

echo "Updating version code..."
./control_ver_code.sh || echo "Skipping version code update."

echo "Updating version name..."
./control_ver_name.sh || echo "Skipping version name update."

echo "Committing changes..."
before_commit_sha=$(git -C "$ROOT_DIR" rev-parse HEAD)
./commit.sh || echo "Skipping commit."
after_commit_sha=$(git -C "$ROOT_DIR" rev-parse HEAD)

if [[ "$before_commit_sha" == "$after_commit_sha" ]]; then
  echo "No new commit was created. Stopping release flow before merge/deploy."
  exit 0
fi

echo "Creating pull request to main..."
./merge.sh ask "$after_commit_sha"

echo "Starting deployment..."
./deploy.sh

echo "Release process completed!"
cd "$ROOT_DIR"
''';

const _allScript = r'''#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
"$SCRIPT_DIR/release.sh" "$@"
''';

const _bumpVersionCodeScript = r'''#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
"$SCRIPT_DIR/control_ver_code.sh" "$@"
''';

const _controlVersionCodeScript = r'''#!/bin/bash
set -euo pipefail

export FASTLANE_SKIP_SCREEN=${FASTLANE_SKIP_SCREEN:-1}
export TTY_SCREEN_WIDTH=${TTY_SCREEN_WIDTH:-120}
export TTY_SCREEN_HEIGHT=${TTY_SCREEN_HEIGHT:-40}

MODE="${1:-ask}"
MANUAL_CODE="${2:-}"
TRACK="${TRACK:-${PLAY_TRACK:-production}}"
do_update=false

if [[ "$MODE" == "yes" ]]; then
  do_update=true
elif [[ "$MODE" == "no" ]]; then
  echo "Skipping version code update."
  exit 0
elif [[ "$MODE" == "manual" ]]; then
  do_update=true
else
  while true; do
    read -r -p "Do you want to update the version code? [Y/n] " versionCodeChoice
    case "${versionCodeChoice}" in
      ''|[Yy]|[Yy][Ee][Ss])
        do_update=true
        break
        ;;
      [Nn]|[Nn][Oo])
        echo "Skipping version code update."
        exit 0
        ;;
      *)
        echo "Please answer Y or n."
        ;;
    esac
  done
fi

if [[ "$do_update" == true ]]; then
  ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
  ANDROID_DIR="$ROOT_DIR/android"
  AUTO_DIR="$ROOT_DIR/auto"

  FASTLANE_CMD="fastlane"
  if [[ "${USE_BUNDLER_FASTLANE:-0}" == "1" ]]; then
    if [[ -f "$ANDROID_DIR/Gemfile" ]] && command -v bundle >/dev/null 2>&1; then
      export BUNDLE_GEMFILE="$ANDROID_DIR/Gemfile"
      FASTLANE_CMD="bundle exec fastlane"
    else
      echo "USE_BUNDLER_FASTLANE=1 but android/Gemfile or bundle is unavailable. Falling back to global fastlane."
    fi
  fi

  if ! command -v fastlane >/dev/null 2>&1 && [[ "$FASTLANE_CMD" == "fastlane" ]]; then
    echo "fastlane not found. Install it or ensure bundle exec fastlane works."
    exit 1
  fi

  cd "$ANDROID_DIR"
  echo "Fetching version codes..."

  run_fastlane_lane() {
    FASTLANE_SKIP_SCREEN=1 TTY_SCREEN_WIDTH=$TTY_SCREEN_WIDTH TTY_SCREEN_HEIGHT=$TTY_SCREEN_HEIGHT \
      $FASTLANE_CMD "$@"
  }

  extract_code_from_output() {
    local marker="$1"
    local output="$2"
    echo "$output" | tr -d '\r' | sed -n "s/.*${marker}:\([0-9][0-9]*\).*/\1/p" | tail -n1
  }

  store_output=$(run_fastlane_lane android fetch_version_code_from_play_store track:"$TRACK" --capture_output 2>&1 || true)
  local_output=$(run_fastlane_lane android get_local_version_code --capture_output 2>&1 || true)

  store_code=$(extract_code_from_output "STORE_CODE_ONLY" "$store_output")
  local_code=$(extract_code_from_output "LOCAL_CODE_ONLY" "$local_output")

  if [[ -z "$store_code" || -z "$local_code" ]]; then
    echo "Could not parse version codes. store='$store_code' local='$local_code'"
    echo "---- fetch_version_code_from_play_store output ----"
    echo "$store_output"
    echo "---- get_local_version_code output ----"
    echo "$local_output"
    exit 1
  fi

  store_code=$((10#$store_code))
  local_code=$((10#$local_code))

  echo
  echo "Local versionCode : $local_code"
  echo "Store versionCode : $store_code"
  echo "----------------------------------------"

  if (( local_code < store_code )); then
    echo "Local code ($local_code) is behind Play Store ($store_code)."
  elif (( local_code > store_code )); then
    echo "Local code ($local_code) is ahead of Play Store ($store_code)."
  else
    echo "Local code ($local_code) matches Play Store ($store_code)."
  fi
  echo

  if [[ "$MODE" == "yes" ]]; then
    run_fastlane_lane android bump_version_code track:"$TRACK"
  elif [[ "$MODE" == "manual" ]]; then
    if [[ ! "$MANUAL_CODE" =~ ^[0-9]+$ ]]; then
      echo "Please provide a valid numeric version code for manual mode."
      exit 1
    fi
    run_fastlane_lane android set_version_code version_code:"$MANUAL_CODE"
  else
    while true; do
      echo "1. Auto bump version code (+1 from Play Store)"
      echo "2. Manually set version code"
      echo "3. Skip"
      read -r -p "Choose (1/2/3): " choice
      case "$choice" in
        1)
          run_fastlane_lane android bump_version_code track:"$TRACK"
          break
          ;;
        2)
          while true; do
            read -r -p "Enter new version code: " new_code
            if [[ "$new_code" =~ ^[0-9]+$ ]]; then
              run_fastlane_lane android set_version_code version_code:"$new_code"
              break 2
            else
              echo "Please enter a valid numeric version code."
            fi
          done
          ;;
        3)
          echo "Skipping version code update."
          break
          ;;
        *)
          echo "Invalid choice, please enter 1, 2, or 3."
          ;;
      esac
    done
  fi

  cd "$AUTO_DIR"
else
  echo "Skipping version code update."
fi
''';

const _controlVersionNameScript = r'''#!/bin/bash
set -euo pipefail

export FASTLANE_SKIP_SCREEN=${FASTLANE_SKIP_SCREEN:-1}
export TTY_SCREEN_WIDTH=${TTY_SCREEN_WIDTH:-120}
export TTY_SCREEN_HEIGHT=${TTY_SCREEN_HEIGHT:-40}

MODE="${1:-ask}"
MANUAL_VERSION="${2:-}"
update_name=false

if [[ "$MODE" == "yes" ]]; then
  update_name=true
elif [[ "$MODE" == "no" ]]; then
  echo "Skipping version name update."
  exit 0
elif [[ "$MODE" == "manual" ]]; then
  update_name=true
else
  while true; do
    read -r -p "Do you want to update the version name? [Y/n] " versionNameChoice
    case "$versionNameChoice" in
      ''|[Yy]|[Yy][Ee][Ss])
        update_name=true
        break
        ;;
      [Nn]|[Nn][Oo])
        echo "Skipping version name update."
        exit 0
        ;;
      *)
        echo "Please answer Y or n."
        ;;
    esac
  done
fi

if [[ "$update_name" == true ]]; then
  ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
  ANDROID_DIR="$ROOT_DIR/android"
  AUTO_DIR="$ROOT_DIR/auto"
  cd "$ANDROID_DIR"

  FASTLANE_CMD="fastlane"
  if [[ "${USE_BUNDLER_FASTLANE:-0}" == "1" ]]; then
    if [[ -f "$ANDROID_DIR/Gemfile" ]] && command -v bundle >/dev/null 2>&1; then
      export BUNDLE_GEMFILE="$ANDROID_DIR/Gemfile"
      FASTLANE_CMD="bundle exec fastlane"
    else
      echo "USE_BUNDLER_FASTLANE=1 but android/Gemfile or bundle is unavailable. Falling back to global fastlane."
    fi
  fi

  if ! command -v fastlane >/dev/null 2>&1 && [[ "$FASTLANE_CMD" == "fastlane" ]]; then
    echo "fastlane not found. Install it or add to your PATH."
    exit 1
  fi

  run_fastlane_lane() {
    FASTLANE_SKIP_SCREEN=1 TTY_SCREEN_WIDTH=$TTY_SCREEN_WIDTH TTY_SCREEN_HEIGHT=$TTY_SCREEN_HEIGHT \
      $FASTLANE_CMD "$@"
  }

  extract_version_name_from_output() {
    local output="$1"
    echo "$output" | tr -d '\r' | sed -n 's/.*VERSION_NAME_ONLY:\([^[:space:]]\+\).*/\1/p' | tail -n1
  }

  bump_version_name() {
    local current="$1"
    local prefix=""
    local ver="$current"

    if [[ "$current" == *_* ]]; then
      prefix="${current%%_*}_"
      ver="${current#*_}"
    fi

    if [[ ! "$ver" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
      return 1
    fi

    IFS='.' read -ra parts <<< "$ver"
    last_index=$(( ${#parts[@]} - 1 ))
    parts[$last_index]=$(( ${parts[$last_index]} + 1 ))

    new_version="${parts[0]}"
    for ((i=1; i<${#parts[@]}; i++)); do
      new_version+=".${parts[$i]}"
    done

    echo "${prefix}${new_version}"
  }

  echo "Fetching current version name..."
  output=$(run_fastlane_lane android get_version_name --capture_output 2>&1 || true)
  CURRENT_VERSION_NAME=$(extract_version_name_from_output "$output")

  if [[ -z "$CURRENT_VERSION_NAME" ]]; then
    echo "Failed to retrieve version name."
    echo "---- get_version_name output ----"
    echo "$output"
    exit 1
  fi

  echo "Current Version Name: $CURRENT_VERSION_NAME"
  echo "----------------------------------------"

  if [[ "$MODE" == "yes" ]]; then
    NEW_VERSION_NAME=$(bump_version_name "$CURRENT_VERSION_NAME") || {
      echo "Cannot auto bump version name '$CURRENT_VERSION_NAME'. Use manual mode."
      exit 1
    }
    echo "Auto bumped version name to: $NEW_VERSION_NAME"
    run_fastlane_lane android update_version_name version_name:"$NEW_VERSION_NAME"
  elif [[ "$MODE" == "manual" && -n "$MANUAL_VERSION" ]]; then
    run_fastlane_lane android update_version_name version_name:"$MANUAL_VERSION"
  else
    while true; do
      echo "1. Auto bump version name"
      echo "2. Manually set version name"
      echo "3. Skip"
      read -r -p "Choose an option (1/2/3): " choice

      case "$choice" in
        1)
          NEW_VERSION_NAME=$(bump_version_name "$CURRENT_VERSION_NAME") || {
            echo "Cannot auto bump version name '$CURRENT_VERSION_NAME'. Choose manual mode."
            continue
          }
          echo "Auto bumped version name to: $NEW_VERSION_NAME"
          run_fastlane_lane android update_version_name version_name:"$NEW_VERSION_NAME"
          break
          ;;
        2)
          read -r -p "Enter the new version name: " NEW_VERSION_NAME
          run_fastlane_lane android update_version_name version_name:"$NEW_VERSION_NAME"
          break
          ;;
        3)
          echo "Skipping version name update."
          break
          ;;
        *)
          echo "Invalid choice, please enter 1, 2, or 3."
          ;;
      esac
    done
  fi
fi

cd "$AUTO_DIR"
''';

const _commitScript = r'''#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

on_interrupt() {
  echo
  echo "Commit interrupted. Skipping commit and moving to next step."
  exit 0
}

trap on_interrupt INT

commitChoice="ask"
if [[ "${1:-}" == "--yes" ]]; then
  commitChoice="yes"
  shift
fi

if [[ "$commitChoice" == "ask" ]]; then
  read -r -p "Do you want to commit the changes? [Y/n] " commitChoice
  commitChoice=$(echo "$commitChoice" | xargs)
fi

if [[ -z "$commitChoice" || "$commitChoice" =~ ^[Yy]([Ee][Ss])?$ ]]; then
  cd "$ROOT_DIR"

  if [ $# -ge 1 ]; then
    COMMIT_MESSAGE="$1"
  else
    read -r -p "Enter commit message: " COMMIT_MESSAGE
    COMMIT_MESSAGE=$(echo "$COMMIT_MESSAGE" | xargs)
  fi

  if [[ -z "$COMMIT_MESSAGE" ]]; then
    echo "Commit message cannot be empty. Skipping commit."
    exit 0
  fi

  if [ $# -ge 3 ]; then
    COMMIT_DESCRIPTION="$3"
  else
    read -r -p "Enter commit description (optional): " COMMIT_DESCRIPTION
    COMMIT_DESCRIPTION=$(echo "$COMMIT_DESCRIPTION" | xargs)
  fi

  if [ $# -ge 2 ]; then
    BRANCH_NAME="$2"
  else
    read -r -p "Enter branch name (leave empty to use current branch): " input_branch
    input_branch=$(echo "$input_branch" | xargs)
    if [ -z "$input_branch" ]; then
      BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
    else
      BRANCH_NAME="$input_branch"
    fi
  fi

  echo "Commit message: $COMMIT_MESSAGE"
  if [[ -n "$COMMIT_DESCRIPTION" ]]; then
    echo "Commit description: $COMMIT_DESCRIPTION"
  fi
  echo "Branch name: $BRANCH_NAME"

  git add .
  if [[ -n "$COMMIT_DESCRIPTION" ]]; then
    git commit -m "$COMMIT_MESSAGE" -m "$COMMIT_DESCRIPTION"
  else
    git commit -m "$COMMIT_MESSAGE"
  fi
  git push origin "$BRANCH_NAME"

  cd "$SCRIPT_DIR"
  echo "Changes committed and pushed to '$BRANCH_NAME'."
else
  echo "Skipping commit."
fi
''';

const _mergeScript = r'''#!/bin/bash
set -euo pipefail

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
TARGET_BRANCH="${TARGET_BRANCH:-main}"
BRANCH_NAME=$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)
RELEASE_COMMIT="${2:-$(git -C "$ROOT_DIR" rev-parse HEAD)}"
WAIT_TIMEOUT_SECONDS="${PR_MERGE_WAIT_SECONDS:-1800}"
POLL_INTERVAL_SECONDS="${PR_MERGE_POLL_INTERVAL:-15}"
mergeChoice="${1:-ask}"

if [[ "$BRANCH_NAME" == "$TARGET_BRANCH" ]]; then
  echo "Current branch is '$TARGET_BRANCH'. Pull request step is not required."
  exit 0
fi

if [[ "$mergeChoice" == "ask" ]]; then
  read -r -p "Do you want to create a pull request to merge '$BRANCH_NAME' into $TARGET_BRANCH? [Y/n] " mergeInput
else
  mergeInput="$mergeChoice"
fi

if [[ -n "$mergeInput" && ! "$mergeInput" =~ ^[Yy]([Ee][Ss])?$ ]]; then
  echo "Merge request canceled. Input received: '$mergeInput'"
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is not installed. Please install it first."
  exit 1
fi

cd "$ROOT_DIR"
echo "Creating a pull request from '$BRANCH_NAME' into '$TARGET_BRANCH'..."

pr_url=$(gh pr list --head "$BRANCH_NAME" --base "$TARGET_BRANCH" --state open --json url --jq '.[0].url')

if [[ -z "$pr_url" ]]; then
  pr_url=$(gh pr create --base "$TARGET_BRANCH" --head "$BRANCH_NAME" \
    --title "Merge '$BRANCH_NAME' into $TARGET_BRANCH" \
    --body "Automated PR after release preparation.")
fi

if [[ -z "$pr_url" ]]; then
  echo "Failed to create or locate a pull request."
  exit 1
fi

echo "Pull request ready: $pr_url"
gh pr view "$pr_url" --web >/dev/null 2>&1 || echo "Unable to open the browser automatically. Open this link manually: $pr_url"

echo "Checking out '$TARGET_BRANCH' and waiting for the pull request to be merged..."
git checkout "$TARGET_BRANCH"
git pull --ff-only origin "$TARGET_BRANCH"

commit_present_on_target() {
  local target_ref="$1"

  if git merge-base --is-ancestor "$RELEASE_COMMIT" "$target_ref" >/dev/null 2>&1; then
    return 0
  fi

  local cherry_output
  cherry_output=$(git cherry "$target_ref" "$RELEASE_COMMIT" 2>/dev/null || true)
  [[ "$cherry_output" == -* ]]
}

elapsed=0

while (( elapsed <= WAIT_TIMEOUT_SECONDS )); do
  git fetch origin "$TARGET_BRANCH"

  if commit_present_on_target "origin/$TARGET_BRANCH"; then
    git pull --ff-only origin "$TARGET_BRANCH"
    echo "Release commit changes are now available on '$TARGET_BRANCH'."
    exit 0
  fi

  pr_state=$(gh pr view "$pr_url" --json state --jq '.state')
  if [[ "$pr_state" == "CLOSED" ]]; then
    echo "Pull request was closed without the release commit changes appearing on '$TARGET_BRANCH'."
    exit 1
  fi

  remaining=$(( WAIT_TIMEOUT_SECONDS - elapsed ))
  echo "Pull request is still open. Waiting for merge... (${remaining}s remaining)"
  sleep "$POLL_INTERVAL_SECONDS"
  elapsed=$(( elapsed + POLL_INTERVAL_SECONDS ))
done

echo "Timed out waiting for the pull request changes to reach '$TARGET_BRANCH'."
exit 1
''';

const _deployScript = r'''#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
ANDROID_DIR="$ROOT_DIR/android"

echo "Deployment Options"

rawArg1="${1:-ask}"
rawArg2="${2:-}"
rawArg3="${3:-}"
rawArg4="${4:-}"
chplayChoice=""
updateDescription=""
playImagesChoice=""

ask_choice() {
  local prompt="$1"
  local var
  read -r -p "$prompt [Y/n] " var
  normalize_choice "${var}"
}

normalize_choice() {
  local raw="$1"
  local normalized
  normalized=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
  case "$normalized" in
    ""|ask) echo "ask" ;;
    1|true|y|yes) echo "yes" ;;
    0|false|n|no) echo "no" ;;
    *) echo "invalid" ;;
  esac
}

extract_version_code() {
  local pubspec_path="$ROOT_DIR/pubspec.yaml"
  [[ -f "$pubspec_path" ]] || return 1
  sed -nE 's/^[[:space:]]*version:[[:space:]]*[^+]+[+]([0-9]+)[[:space:]]*$/\1/p' "$pubspec_path" | head -n1
}

fastlane_cmd() {
  if [[ "${USE_BUNDLER_FASTLANE:-0}" == "1" ]]; then
    if [[ -f "$ANDROID_DIR/Gemfile" ]] && command -v bundle >/dev/null 2>&1; then
      export BUNDLE_GEMFILE="$ANDROID_DIR/Gemfile"
      echo "bundle exec fastlane"
      return
    fi
    echo "USE_BUNDLER_FASTLANE=1 but android/Gemfile or bundle is unavailable. Falling back to global fastlane." >&2
  fi
  echo "fastlane"
}

run_fastlane_lane() {
  local cmd
  cmd="$(fastlane_cmd)"
  FASTLANE_SKIP_SCREEN=1 TTY_SCREEN_WIDTH="${TTY_SCREEN_WIDTH:-120}" TTY_SCREEN_HEIGHT="${TTY_SCREEN_HEIGHT:-40}" \
    $cmd "$@"
}

arg1Choice=$(normalize_choice "${rawArg1}")
arg2Choice=$(normalize_choice "${rawArg2}")

if [[ "$arg1Choice" == "invalid" ]]; then
  echo "Invalid first argument: '${rawArg1}'. Use ask|yes|no."
  exit 1
fi

useLegacyArgs="false"
if [[ "${DEPLOY_LEGACY_ARGS:-0}" == "1" ]]; then
  useLegacyArgs="true"
elif [[ -n "$rawArg3" && ( "${arg2Choice}" == "yes" || "${arg2Choice}" == "no" ) ]]; then
  useLegacyArgs="true"
fi

if [[ "$useLegacyArgs" == "true" ]]; then
  chplayChoice="${arg2Choice}"
  updateDescription="${rawArg3}"
  playImagesChoice=$(normalize_choice "${UPLOAD_PLAY_IMAGES:-${rawArg4:-ask}}")
else
  chplayChoice="${arg1Choice}"
  updateDescription="${rawArg2}"
  playImagesChoice=$(normalize_choice "${UPLOAD_PLAY_IMAGES:-${rawArg3:-ask}}")
fi

if [[ "$playImagesChoice" == "invalid" ]]; then
  echo "Invalid Play images choice. Use ask|yes|no, or UPLOAD_PLAY_IMAGES=1|0."
  exit 1
fi

if [[ "$chplayChoice" == "ask" ]]; then
  if [[ ! -t 0 ]]; then
    echo "No interactive terminal detected. Pass first argument as yes or no."
    exit 1
  fi
  chplayChoice=$(ask_choice "Do you want to upload to Google Play?")
  if [[ "$chplayChoice" == "invalid" || "$chplayChoice" == "ask" ]]; then
    echo "Invalid response. Please answer yes or no."
    exit 1
  fi
fi
echo

current_dir=$(pwd)

if [[ "$chplayChoice" == "yes" ]]; then
  echo "Uploading to Google Play..."

  versionCode="$(extract_version_code || true)"
  existingChangelogPath=""
  if [[ -n "$versionCode" ]]; then
    candidateChangelogPath="$ROOT_DIR/android/fastlane/metadata/android/vi/changelogs/${versionCode}.txt"
    if [[ -s "$candidateChangelogPath" ]]; then
      existingChangelogPath="$candidateChangelogPath"
      echo "Found existing changelog for version code ${versionCode}: ${existingChangelogPath}"
    fi
  fi

  if [[ -z "$updateDescription" && -z "$existingChangelogPath" ]]; then
    if [[ -t 0 ]]; then
      read -r -p "Enter Google Play update description (What's new): " updateDescription
    else
      echo "Update description is required in non-interactive mode unless a versioned changelog exists."
      exit 1
    fi
  fi

  if [[ -z "$updateDescription" && -z "$existingChangelogPath" ]]; then
    echo "Update description is required, or create a changelog file by version code. Exiting."
    exit 1
  fi

  if [[ "$playImagesChoice" == "ask" ]]; then
    if [[ -t 0 ]]; then
      playImagesChoice=$(ask_choice "Upload Play listing images/app icon/screenshots?")
      if [[ "$playImagesChoice" == "invalid" || "$playImagesChoice" == "ask" ]]; then
        echo "Invalid response. Please answer yes or no."
        exit 1
      fi
    else
      playImagesChoice="yes"
    fi
  fi

  uploadPlayImagesEnv="0"
  if [[ "$playImagesChoice" == "yes" ]]; then
    uploadPlayImagesEnv="1"
    dart "$SCRIPT_DIR/check_play_images.dart"
  else
    echo "Skipping Play listing images/app icon/screenshots upload."
  fi

  cd "$ANDROID_DIR" || exit 1

  if [[ -n "$updateDescription" ]]; then
    UPLOAD_PLAY_IMAGES="$uploadPlayImagesEnv" SKIP_PLAY_IMAGE_CHECK=1 \
      run_fastlane_lane android upload_to_chplay update_description:"${updateDescription}"
  else
    UPLOAD_PLAY_IMAGES="$uploadPlayImagesEnv" SKIP_PLAY_IMAGE_CHECK=1 \
      run_fastlane_lane android upload_to_chplay
  fi

  cd "$current_dir" || exit 1
else
  echo "Skipping Google Play upload (choice: no)."
fi

echo "Deployment process completed!"
''';

const _playImagesValidator = r'''import 'dart:io';
import 'dart:typed_data';

const imageExtensions = {'.png', '.jpg', '.jpeg'};
const mb = 1024 * 1024;

class ImageInfo {
  const ImageInfo({
    required this.format,
    required this.width,
    required this.height,
  });

  final String format;
  final int width;
  final int height;
}

String extensionOf(String path) {
  final index = path.lastIndexOf('.');
  return index == -1 ? '' : path.substring(index).toLowerCase();
}

ImageInfo? detectImage(File file) {
  final bytes = file.readAsBytesSync();

  if (_isPng(bytes)) {
    final data = ByteData.sublistView(bytes);
    return ImageInfo(
      format: 'PNG',
      width: data.getUint32(16),
      height: data.getUint32(20),
    );
  }

  if (_isJpeg(bytes)) {
    return _detectJpeg(bytes);
  }

  return null;
}

bool _isPng(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 24) return false;

  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }

  return true;
}

bool _isJpeg(Uint8List bytes) {
  return bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8;
}

ImageInfo? _detectJpeg(Uint8List bytes) {
  var index = 2;

  while (index < bytes.length) {
    while (index < bytes.length && bytes[index] != 0xFF) {
      index++;
    }
    while (index < bytes.length && bytes[index] == 0xFF) {
      index++;
    }
    if (index >= bytes.length) return null;

    final marker = bytes[index++];
    if (marker == 0xD9 || marker == 0xDA) return null;
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) continue;
    if (index + 1 >= bytes.length) return null;

    final length = (bytes[index] << 8) + bytes[index + 1];
    index += 2;

    if (length < 2 || index + length - 2 > bytes.length) return null;

    if (_isStartOfFrame(marker)) {
      if (length < 7) return null;

      final height = (bytes[index + 1] << 8) + bytes[index + 2];
      final width = (bytes[index + 3] << 8) + bytes[index + 4];
      return ImageInfo(format: 'JPEG', width: width, height: height);
    }

    index += length - 2;
  }

  return null;
}

bool _isStartOfFrame(int marker) {
  return const {
    0xC0,
    0xC1,
    0xC2,
    0xC3,
    0xC5,
    0xC6,
    0xC7,
    0xC9,
    0xCA,
    0xCB,
    0xCD,
    0xCE,
    0xCF,
  }.contains(marker);
}

List<File> imageFiles(Directory directory) {
  if (!directory.existsSync()) return [];

  return directory
      .listSync()
      .whereType<File>()
      .where((file) => imageExtensions.contains(extensionOf(file.path)))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

List<String> unsupportedFiles(Directory directory) {
  if (!directory.existsSync()) return [];

  return directory
      .listSync()
      .whereType<File>()
      .where((file) => !file.uri.pathSegments.last.startsWith('.'))
      .where((file) => !imageExtensions.contains(extensionOf(file.path)))
      .map((file) => file.uri.pathSegments.last)
      .toList()
    ..sort();
}

({ImageInfo? info, List<String> errors}) validateFile(File file, int maxBytes) {
  final errors = <String>[];
  final ext = extensionOf(file.path);
  final info = imageExtensions.contains(ext) ? detectImage(file) : null;

  if (info == null) errors.add('must be PNG or JPEG');
  if (file.lengthSync() > maxBytes) {
    errors.add('must be maximum ${maxBytes ~/ mb} MB');
  }

  return (info: info, errors: errors);
}

List<String> validateNamedImage({
  required Directory imagesDir,
  required String label,
  required String baseName,
  String? folderName,
  required int maxBytes,
  required int requiredWidth,
  required int requiredHeight,
}) {
  final rootMatches = imageExtensions
      .map(
        (ext) =>
            File('${imagesDir.path}${Platform.pathSeparator}$baseName$ext'),
      )
      .where((file) => file.existsSync())
      .toList();
  final folder = folderName == null
      ? null
      : Directory('${imagesDir.path}${Platform.pathSeparator}$folderName');
  final folderMatches = folder == null ? <File>[] : imageFiles(folder);
  final matches = folderMatches.isNotEmpty ? folderMatches : rootMatches;
  final errors = <String>[];

  if (folder != null) {
    errors.addAll(
      unsupportedFiles(
        folder,
      ).map((name) => '$label: $folderName/$name must be PNG or JPEG'),
    );
  }

  if (matches.isEmpty) {
    final folderHint = folderName == null ? '' : ' or $folderName/';
    errors.add('$label: missing $baseName.png/.jpg/.jpeg$folderHint');
    return errors;
  }

  if (matches.length > 1) {
    errors.add('$label: keep only one $baseName image');
  }

  for (final file in matches) {
    final result = validateFile(file, maxBytes);
    final name = file.uri.pathSegments.last;
    errors.addAll(result.errors.map((message) => '$label: $name $message'));

    final info = result.info;
    if (info == null) continue;

    if (info.width != requiredWidth || info.height != requiredHeight) {
      errors.add(
        '$label: $name must be ${requiredWidth}x${requiredHeight}px, got ${info.width}x${info.height}px',
      );
    }
  }

  return errors;
}

List<String> validateScreenshots({
  required Directory imagesDir,
  required String label,
  required String folderName,
  required int minCount,
  required int maxCount,
}) {
  final folder = Directory(
    '${imagesDir.path}${Platform.pathSeparator}$folderName',
  );
  final files = imageFiles(folder);
  final errors = <String>[];

  errors.addAll(
    unsupportedFiles(folder).map((name) => '$label: $name must be PNG or JPEG'),
  );

  if (files.length < minCount) {
    errors.add(
      '$label: needs at least $minCount screenshot(s), found ${files.length}',
    );
  }

  if (files.length > maxCount) {
    errors.add(
      '$label: allows at most $maxCount screenshots, found ${files.length}',
    );
  }

  for (final file in files) {
    final result = validateFile(file, 8 * mb);
    final name = file.uri.pathSegments.last;
    errors.addAll(result.errors.map((message) => '$label: $name $message'));

    final info = result.info;
    if (info == null) continue;

    if ([info.width, info.height].any((side) => side < 320 || side > 3840)) {
      errors.add(
        '$label: $name sides must be between 320px and 3840px, got ${info.width}x${info.height}px',
      );
    }
  }

  return errors;
}

void main() {
  final scriptDir = File.fromUri(Platform.script).parent;
  final rootDir = scriptDir.parent;
  final imagesDir = Directory(
    '${rootDir.path}${Platform.pathSeparator}android'
    '${Platform.pathSeparator}fastlane'
    '${Platform.pathSeparator}metadata'
    '${Platform.pathSeparator}android'
    '${Platform.pathSeparator}vi'
    '${Platform.pathSeparator}images',
  );

  final errors = <String>[
    ...validateNamedImage(
      imagesDir: imagesDir,
      label: 'App logo',
      baseName: 'icon',
      folderName: 'icon',
      maxBytes: 1 * mb,
      requiredWidth: 512,
      requiredHeight: 512,
    ),
    ...validateNamedImage(
      imagesDir: imagesDir,
      label: 'Featured image',
      baseName: 'featureGraphic',
      folderName: 'featureGraphic',
      maxBytes: 15 * mb,
      requiredWidth: 1024,
      requiredHeight: 500,
    ),
    ...validateScreenshots(
      imagesDir: imagesDir,
      label: 'Phone screenshots',
      folderName: 'phoneScreenshots',
      minCount: 2,
      maxCount: 8,
    ),
    ...validateScreenshots(
      imagesDir: imagesDir,
      label: '7-inch tablet screenshots',
      folderName: 'sevenInchScreenshots',
      minCount: 0,
      maxCount: 8,
    ),
  ];

  if (errors.isEmpty) {
    stdout.writeln('Google Play images look good.');
    exitCode = 0;
    return;
  }

  stderr.writeln('Google Play image check failed:');
  for (final error in errors) {
    stderr.writeln('- $error');
  }
  exitCode = 1;
}
''';
