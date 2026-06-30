class AppStoreCredentials {
  const AppStoreCredentials({
    this.p8PrivateKey,
    this.keyId,
    this.issuerId,
    this.teamId,
    this.inHouse = false,
  });

  final String? p8PrivateKey;
  final String? keyId;
  final String? issuerId;
  final String? teamId;
  final bool inHouse;

  bool get hasP8PrivateKey => _hasValue(p8PrivateKey);
  bool get hasKeyId => _hasValue(keyId);
  bool get hasIssuerId => _hasValue(issuerId);
  bool get hasTeamId => _hasValue(teamId);

  bool get hasRequiredCredentials {
    return hasP8PrivateKey && hasKeyId && hasIssuerId;
  }

  AppStoreCredentialMetadata get metadata {
    return AppStoreCredentialMetadata(
      hasP8PrivateKey: hasP8PrivateKey,
      hasKeyId: hasKeyId,
      hasIssuerId: hasIssuerId,
      hasTeamId: hasTeamId,
      inHouse: inHouse,
    );
  }

  static bool _hasValue(String? value) {
    return value != null && value.trim().isNotEmpty;
  }
}

class AppStoreCredentialMetadata {
  const AppStoreCredentialMetadata({
    this.hasP8PrivateKey = false,
    this.hasKeyId = false,
    this.hasIssuerId = false,
    this.hasTeamId = false,
    this.inHouse = false,
  });

  final bool hasP8PrivateKey;
  final bool hasKeyId;
  final bool hasIssuerId;
  final bool hasTeamId;
  final bool inHouse;

  bool get hasRequiredCredentials {
    return hasP8PrivateKey && hasKeyId && hasIssuerId;
  }
}
