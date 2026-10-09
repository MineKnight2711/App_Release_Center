import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../models/automation_models.dart';
import '../models/qa_models.dart';

class SourceDiscoveryException implements Exception {
  const SourceDiscoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SourceDiscoveryService {
  const SourceDiscoveryService();

  Future<QaSource> discover(String rawPath) async {
    final directory = Directory(rawPath);
    if (!await directory.exists()) {
      throw const SourceDiscoveryException('Thư mục nguồn không tồn tại.');
    }

    final normalizedPath = directory.absolute.path;
    final manifest = File(
      '$normalizedPath${Platform.pathSeparator}.fiza-qa'
      '${Platform.pathSeparator}project.yaml',
    );

    if (await manifest.exists()) {
      return _fromManifest(directory, manifest);
    }

    return _infer(directory);
  }

  Future<QaSource> _fromManifest(Directory directory, File manifest) async {
    try {
      final yaml = loadYaml(await manifest.readAsString());
      if (yaml is! YamlMap) {
        throw const SourceDiscoveryException(
          'Manifest phải là một YAML object.',
        );
      }

      final id = _requiredString(yaml, 'id');
      final name = _requiredString(yaml, 'name');
      final type = SourceType.parse(yaml['type']?.toString());
      final apps = _apps(yaml['apps']);
      final suitesNode = yaml['suites'];
      // A project QA Desk only operates itself needs no suite of its own.
      if ((suitesNode is! YamlList || suitesNode.isEmpty) && apps.isEmpty) {
        throw const SourceDiscoveryException(
          'Manifest phải khai báo ít nhất một test suite hoặc một app.',
        );
      }

      final suites = (suitesNode is YamlList ? suitesNode : YamlList())
          .map((node) {
            if (node is! YamlMap) {
              throw const SourceDiscoveryException(
                'Suite phải là một YAML object.',
              );
            }
            final executable = _requiredString(node, 'executable');
            if (!_allowedExecutables.contains(executable.toLowerCase())) {
              throw SourceDiscoveryException(
                'Executable "$executable" chưa nằm trong allowlist.',
              );
            }

            return QaSuite(
              id: _requiredString(node, 'id'),
              name: _requiredString(node, 'name'),
              executable: executable,
              arguments: _yamlStringList(node['arguments']),
              description: node['description']?.toString() ?? '',
              tags: _yamlStringList(node['tags']),
              requiresDevice: node['requiresDevice'] == true,
              requiresPhysicalDevice: node['requiresPhysicalDevice'] == true,
              requiresAppium: node['requiresAppium'] == true,
              captureScreenshotOnFailure:
                  node['captureScreenshotOnFailure'] != false,
              selected: node['selected'] != false,
            );
          })
          .toList(growable: false);

      return QaSource(
        id: id,
        name: name,
        path: directory.absolute.path,
        type: type,
        suites: suites,
        manifestBacked: true,
        apps: apps,
      );
    } on SourceDiscoveryException {
      rethrow;
    } on Object catch (error) {
      throw SourceDiscoveryException('Không đọc được manifest: $error');
    }
  }

  Future<QaSource> _infer(Directory directory) async {
    final separator = Platform.pathSeparator;
    final pubspec = File('${directory.path}${separator}pubspec.yaml');
    final package = File('${directory.path}${separator}package.json');
    final playwrightConfigs = [
      'playwright.config.ts',
      'playwright.config.js',
      'playwright.config.mjs',
    ];

    if (await pubspec.exists()) {
      final contents = await pubspec.readAsString();
      final parsed = loadYaml(contents);
      final name = parsed is YamlMap && parsed['name'] != null
          ? parsed['name'].toString()
          : directory.path.split(separator).last;
      return QaSource(
        id: _slug(name),
        name: name,
        path: directory.absolute.path,
        type: SourceType.flutter,
        suites: const [
          QaSuite(
            id: 'analyze',
            name: 'Flutter Analyze',
            executable: 'flutter',
            arguments: ['analyze'],
            tags: ['static'],
          ),
          QaSuite(
            id: 'unit-widget',
            name: 'Unit & Widget Tests',
            executable: 'flutter',
            arguments: ['test', '--reporter', 'compact'],
            tags: ['test'],
          ),
        ],
        manifestBacked: false,
      );
    }

    if (await package.exists()) {
      final json =
          jsonDecode(await package.readAsString()) as Map<String, dynamic>;
      final name =
          json['name']?.toString() ?? directory.path.split(separator).last;
      final scripts = Map<String, dynamic>.from(
        json['scripts'] as Map? ?? const <String, dynamic>{},
      );
      final hasPlaywright = await _anyExists(directory, playwrightConfigs);
      final suites = <QaSuite>[];

      if (scripts.containsKey('build')) {
        suites.add(
          const QaSuite(
            id: 'build',
            name: 'Production Build',
            executable: 'npm',
            arguments: ['run', 'build'],
            tags: ['build'],
          ),
        );
      }
      if (scripts.containsKey('test')) {
        suites.add(
          const QaSuite(
            id: 'test',
            name: 'Project Tests',
            executable: 'npm',
            arguments: ['test', '--', '--run'],
            tags: ['test'],
          ),
        );
      }
      if (hasPlaywright) {
        suites.add(
          const QaSuite(
            id: 'e2e',
            name: 'Playwright E2E',
            executable: 'npx',
            arguments: ['playwright', 'test'],
            tags: ['e2e'],
          ),
        );
      }

      final nodeTests = await _nodeTestFiles(directory);
      if (!scripts.containsKey('test') && nodeTests.isNotEmpty) {
        suites.add(
          QaSuite(
            id: 'node-contract',
            name: 'Node Contract Tests',
            executable: 'node',
            arguments: ['--test', ...nodeTests],
            tags: const ['contract'],
          ),
        );
      }

      if (suites.isEmpty) {
        throw const SourceDiscoveryException(
          'Đã nhận diện Node/Web project nhưng chưa tìm thấy test/build script.',
        );
      }

      return QaSource(
        id: _slug(name),
        name: name,
        path: directory.absolute.path,
        type: hasPlaywright ? SourceType.playwright : SourceType.node,
        suites: suites,
        manifestBacked: false,
      );
    }

    throw const SourceDiscoveryException(
      'Không nhận ra loại dự án. Cần pubspec.yaml, package.json hoặc manifest .fiza-qa/project.yaml.',
    );
  }

  Future<bool> _anyExists(Directory directory, List<String> names) async {
    for (final name in names) {
      if (await File(
        '${directory.path}${Platform.pathSeparator}$name',
      ).exists()) {
        return true;
      }
    }
    return false;
  }

  Future<List<String>> _nodeTestFiles(Directory directory) async {
    final tests = Directory('${directory.path}${Platform.pathSeparator}tests');
    if (!await tests.exists()) return [];

    final paths = <String>[];
    await for (final entity in tests.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File &&
          (entity.path.endsWith('.test.mjs') ||
              entity.path.endsWith('.test.js') ||
              entity.path.endsWith('.test.cjs'))) {
        paths.add(entity.path.substring(directory.path.length + 1));
      }
    }
    paths.sort();
    return paths;
  }
}

const _allowedExecutables = {
  'flutter',
  'dart',
  'node',
  'npm',
  'npx',
  'adb',
  'appium',
};

/// Reads the optional `apps:` list: the apps QA Desk operates itself.
List<QaApp> _apps(dynamic node) {
  if (node == null) return const [];
  if (node is! YamlList) {
    throw const SourceDiscoveryException('"apps" phải là một YAML list.');
  }
  final apps = <QaApp>[];
  for (final item in node) {
    if (item is! YamlMap) {
      throw const SourceDiscoveryException('Mỗi app phải là một YAML object.');
    }
    final id = _requiredString(item, 'id');
    final platform = QaAppPlatform.parse(item['platform']?.toString());
    final environmentsNode = item['environments'];
    if (environmentsNode is! YamlMap || environmentsNode.isEmpty) {
      throw SourceDiscoveryException(
        'App "$id" phải khai ít nhất một môi trường trong "environments".',
      );
    }
    final environments = <QaAppEnvironment>[];
    for (final entry in environmentsNode.entries) {
      final name = entry.key.toString();
      final config = entry.value is YamlMap ? entry.value as YamlMap : null;
      final environment = QaAppEnvironment(
        name: name,
        appId: config?['appId']?.toString() ?? '',
        url: config?['url']?.toString() ?? '',
        build: config?['build']?.toString() ?? '',
        production: config?['production'] == true,
      );
      if (platform == QaAppPlatform.android && environment.appId.isEmpty) {
        throw SourceDiscoveryException(
          'Môi trường "$name" của app "$id" thiếu "appId".',
        );
      }
      if (platform == QaAppPlatform.web && environment.url.isEmpty) {
        throw SourceDiscoveryException(
          'Môi trường "$name" của app "$id" thiếu "url".',
        );
      }
      environments.add(environment);
    }
    apps.add(
      QaApp(
        id: id,
        name: item['name']?.toString() ?? id,
        platform: platform,
        environments: environments,
        loginFlow: item['login']?.toString() ?? '',
        cleanupFlow: item['cleanup']?.toString() ?? '',
        productionGuard: _yamlStringList(item['productionGuard']),
      ),
    );
  }
  return apps;
}

String _requiredString(YamlMap map, String key) {
  final value = map[key]?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw SourceDiscoveryException('Thiếu trường bắt buộc "$key".');
  }
  return value;
}

List<String> _yamlStringList(dynamic value) {
  if (value == null) return const [];
  if (value is! YamlList && value is! List) {
    throw const SourceDiscoveryException('Giá trị phải là một YAML list.');
  }
  return (value as Iterable<dynamic>)
      .map((item) => item.toString())
      .toList(growable: false);
}

String _slug(String input) {
  final slug = input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'source-${input.hashCode.abs()}' : slug;
}
