import 'dart:convert';

import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything the connect form should already know the next time it opens.
///
/// The password is deliberately not part of this: it lives in the OS keychain
/// through [MailCleanerSettingsStore], and only when the user asks for it.
class MailCleanerSettings {
  const MailCleanerSettings({
    this.host = 'pro216.emailserver.vn',
    this.port = 993,
    this.account = '',
    this.folder = 'INBOX',
    this.rememberPassword = false,
  });

  factory MailCleanerSettings.fromJson(Map<String, dynamic> json) {
    final port = json['port'];
    return MailCleanerSettings(
      host: (json['host'] as String?)?.trim().isNotEmpty == true
          ? (json['host'] as String).trim()
          : const MailCleanerSettings().host,
      port: port is int && port >= 1 && port <= 65535
          ? port
          : const MailCleanerSettings().port,
      account: (json['account'] as String?)?.trim() ?? '',
      folder: (json['folder'] as String?)?.trim().isNotEmpty == true
          ? (json['folder'] as String).trim()
          : const MailCleanerSettings().folder,
      rememberPassword: json['rememberPassword'] as bool? ?? false,
    );
  }

  final String host;
  final int port;
  final String account;
  final String folder;

  /// Whether the password may be kept in the OS keychain between sessions.
  final bool rememberPassword;

  MailCleanerSettings copyWith({
    String? host,
    int? port,
    String? account,
    String? folder,
    bool? rememberPassword,
  }) {
    return MailCleanerSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      account: account ?? this.account,
      folder: folder ?? this.folder,
      rememberPassword: rememberPassword ?? this.rememberPassword,
    );
  }

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'account': account,
    'folder': folder,
    'rememberPassword': rememberPassword,
  };
}

/// Keeps the connection details for the mail cleaner between sessions.
///
/// Host, port, account and folder are ordinary preferences. The password is
/// held apart in secure storage and written only while
/// [MailCleanerSettings.rememberPassword] is on, so the default stays what the
/// standalone tool promised: a password that lives no longer than the session.
class MailCleanerSettingsStore {
  MailCleanerSettingsStore({SecureKeyValueStore? secureStore})
    : _secureStore = secureStore ?? FlutterSecureKeyValueStore();

  final SecureKeyValueStore _secureStore;

  Future<MailCleanerSettings> read() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return const MailCleanerSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const MailCleanerSettings();
      return MailCleanerSettings.fromJson(decoded);
    } on FormatException {
      // A settings blob this app can no longer read is not worth an error on
      // the way in; the form falls back to its defaults.
      return const MailCleanerSettings();
    }
  }

  Future<void> save(MailCleanerSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_settingsKey, jsonEncode(settings.toJson()));
    if (!settings.rememberPassword) await savePassword(null);
  }

  Future<String?> readPassword() => _secureStore.read(key: _passwordKey);

  Future<void> savePassword(String? password) async {
    if (password == null || password.isEmpty) {
      await _secureStore.delete(key: _passwordKey);
      return;
    }
    await _secureStore.write(key: _passwordKey, value: password);
  }
}

const _settingsKey = 'mail_cleaner_settings';
const _passwordKey = 'mail_cleaner.password';
