import 'dart:io';

import 'package:app_management_center/app/modules/qa_desk/services/source_discovery_service.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln('Usage: dart run tool/validate_sources.dart <source> [...]');
    exitCode = 64;
    return;
  }

  var failed = false;
  for (final path in arguments) {
    try {
      final source = await const SourceDiscoveryService().discover(path);
      stdout.writeln(
        'OK ${source.id} (${source.type.label}) - ${source.suites.length} suite(s)'
        '${source.apps.isEmpty ? '' : ', ${source.apps.length} app(s)'}',
      );
      for (final suite in source.suites) {
        stdout.writeln('  - ${suite.id}: ${suite.commandPreview}');
      }
      for (final app in source.apps) {
        final environments = [
          for (final environment in app.environments)
            '${environment.name}${environment.isProduction ? ' (production)' : ''}',
        ];
        stdout.writeln(
          '  - app ${app.id} [${app.platform.value}]: ${environments.join(', ')}'
          '${app.loginFlow.isEmpty ? ', no login flow' : ', login ${app.loginFlow}'}',
        );
        final login = File('$path/.fiza-qa/${app.loginFlow}');
        if (app.loginFlow.isNotEmpty && !login.existsSync()) {
          failed = true;
          stderr.writeln('ERROR $path: login flow ${login.path} is missing');
        }
      }
    } on Object catch (error) {
      failed = true;
      stderr.writeln('ERROR $path: $error');
    }
  }
  if (failed) exitCode = 1;
}
