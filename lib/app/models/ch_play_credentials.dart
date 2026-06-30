class ChPlayCredentials {
  const ChPlayCredentials({
    this.googlePlayJson,
    this.jksPath,
    this.keyAlias,
    this.storePassword,
    this.keyPassword,
  });

  final String? googlePlayJson;
  final String? jksPath;
  final String? keyAlias;
  final String? storePassword;
  final String? keyPassword;

  bool get hasGooglePlayJson => _hasValue(googlePlayJson);
  bool get hasJksPath => _hasValue(jksPath);
  bool get hasKeyAlias => _hasValue(keyAlias);
  bool get hasStorePassword => _hasValue(storePassword);
  bool get hasKeyPassword => _hasValue(keyPassword);

  ChPlayCredentialMetadata get metadata {
    return ChPlayCredentialMetadata(
      hasGooglePlayJson: hasGooglePlayJson,
      hasJksPath: hasJksPath,
      hasKeyAlias: hasKeyAlias,
      hasStorePassword: hasStorePassword,
      hasKeyPassword: hasKeyPassword,
    );
  }

  static bool _hasValue(String? value) {
    return value != null && value.trim().isNotEmpty;
  }
}

class ChPlayCredentialMetadata {
  const ChPlayCredentialMetadata({
    this.hasGooglePlayJson = false,
    this.hasJksPath = false,
    this.hasKeyAlias = false,
    this.hasStorePassword = false,
    this.hasKeyPassword = false,
  });

  final bool hasGooglePlayJson;
  final bool hasJksPath;
  final bool hasKeyAlias;
  final bool hasStorePassword;
  final bool hasKeyPassword;

  bool get hasAnySigningCredential {
    return hasJksPath || hasKeyAlias || hasStorePassword || hasKeyPassword;
  }
}
