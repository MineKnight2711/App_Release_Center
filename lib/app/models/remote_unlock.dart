class RemoteUnlockState {
  const RemoteUnlockState({
    this.installed = false,
    this.enabled = false,
    this.keyId = '',
    this.modulus = '',
    this.exponent = '',
    this.challenge = '',
    this.expiresAt,
    this.accountName = '',
    this.error = '',
  });

  final bool installed;
  final bool enabled;
  final String keyId;
  final String modulus;
  final String exponent;
  final String challenge;
  final DateTime? expiresAt;
  final String accountName;
  final String error;

  bool get ready =>
      installed &&
      enabled &&
      keyId.isNotEmpty &&
      modulus.isNotEmpty &&
      exponent.isNotEmpty &&
      challenge.isNotEmpty &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now());

  Map<String, Object?> toJson() => {
    'installed': installed,
    'enabled': enabled,
    'keyId': keyId,
    'modulus': modulus,
    'exponent': exponent,
    'challenge': challenge,
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    'accountName': accountName,
    if (error.isNotEmpty) 'error': error,
  };

  factory RemoteUnlockState.fromJson(Map<String, Object?> json) {
    return RemoteUnlockState(
      installed: json['installed'] == true,
      enabled: json['enabled'] == true,
      keyId: _text(json['keyId']),
      modulus: _text(json['modulus']),
      exponent: _text(json['exponent']),
      challenge: _text(json['challenge']),
      expiresAt: DateTime.tryParse(_text(json['expiresAt'])),
      accountName: _text(json['accountName']),
      error: _text(json['error']),
    );
  }
}

String _text(Object? value) => value?.toString().trim() ?? '';
