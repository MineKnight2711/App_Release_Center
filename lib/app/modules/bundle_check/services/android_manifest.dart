import 'dart:typed_data';

import 'proto_reader.dart';

/// One attribute of a manifest element, as aapt2 compiled it.
class ManifestAttribute {
  const ManifestAttribute({
    required this.name,
    required this.value,
    this.intValue,
    this.boolValue,
    this.referenceName,
  });

  final String name;

  /// The source text, e.g. `73`, `true`, `@string/app_name`.
  final String value;
  final int? intValue;
  final bool? boolValue;

  /// `string/app_name` when the attribute points at a resource.
  final String? referenceName;

  bool get isReference => referenceName != null;
}

class ManifestElement {
  const ManifestElement({
    required this.name,
    required this.attributes,
    required this.children,
  });

  final String name;
  final Map<String, ManifestAttribute> attributes;
  final List<ManifestElement> children;

  ManifestAttribute? operator [](String attribute) => attributes[attribute];

  Iterable<ManifestElement> childrenNamed(String elementName) {
    return children.where((child) => child.name == elementName);
  }

  ManifestElement? firstChild(String elementName) {
    for (final child in children) {
      if (child.name == elementName) return child;
    }
    return null;
  }
}

class ManifestMetaData {
  const ManifestMetaData({
    required this.name,
    required this.value,
    this.referenceName,
  });

  final String name;
  final String value;
  final String? referenceName;
}

/// What the checks need from `AndroidManifest.xml`, read once.
class ManifestInfo {
  const ManifestInfo({
    required this.packageName,
    required this.versionCode,
    required this.versionName,
    required this.minSdk,
    required this.targetSdk,
    required this.debuggable,
    required this.testOnly,
    required this.usesCleartextTraffic,
    required this.hasNetworkSecurityConfig,
    required this.permissions,
    required this.metaData,
    required this.launcherActivity,
  });

  final String packageName;
  final int? versionCode;
  final String? versionName;
  final int? minSdk;
  final int? targetSdk;
  final bool debuggable;
  final bool testOnly;
  final bool? usesCleartextTraffic;
  final bool hasNetworkSecurityConfig;
  final List<String> permissions;
  final List<ManifestMetaData> metaData;
  final String? launcherActivity;

  static ManifestElement parseElement(Uint8List data) {
    final root = ProtoMessage.parse(data).message(1);
    if (root == null) {
      throw const FormatException('AndroidManifest.xml không có element gốc.');
    }
    return _element(root);
  }

  static ManifestInfo parse(Uint8List data) => fromElement(parseElement(data));

  static ManifestInfo fromElement(ManifestElement manifest) {
    if (manifest.name != 'manifest') {
      throw FormatException(
        'Element gốc là <${manifest.name}>, không phải <manifest>.',
      );
    }
    final usesSdk = manifest.firstChild('uses-sdk');
    final application = manifest.firstChild('application');

    return ManifestInfo(
      packageName: manifest['package']?.value ?? '',
      versionCode: _int(manifest['versionCode']),
      versionName: manifest['versionName']?.value,
      minSdk: _int(usesSdk?['minSdkVersion']),
      targetSdk: _int(usesSdk?['targetSdkVersion']),
      debuggable: _bool(application?['debuggable']) ?? false,
      testOnly: _bool(application?['testOnly']) ?? false,
      usesCleartextTraffic: _bool(application?['usesCleartextTraffic']),
      hasNetworkSecurityConfig: application?['networkSecurityConfig'] != null,
      permissions: [
        for (final child in manifest.children)
          if (child.name == 'uses-permission' ||
              child.name == 'uses-permission-sdk-23')
            if (child['name']?.value case final name? when name.isNotEmpty)
              name,
      ],
      metaData: [
        for (final meta
            in application?.childrenNamed('meta-data') ??
                const <ManifestElement>[])
          if (meta['name']?.value case final name? when name.isNotEmpty)
            ManifestMetaData(
              name: name,
              value: (meta['value'] ?? meta['resource'])?.value ?? '',
              referenceName: (meta['value'] ?? meta['resource'])?.referenceName,
            ),
      ],
      launcherActivity: application == null ? null : _launcher(application),
    );
  }

  static String? _launcher(ManifestElement application) {
    for (final activity in application.children) {
      if (activity.name != 'activity' && activity.name != 'activity-alias') {
        continue;
      }
      if (_bool(activity['enabled']) == false) continue;
      for (final filter in activity.childrenNamed('intent-filter')) {
        final isMain = filter
            .childrenNamed('action')
            .any((a) => a['name']?.value == 'android.intent.action.MAIN');
        final isLauncher = filter
            .childrenNamed('category')
            .any((c) => c['name']?.value == 'android.intent.category.LAUNCHER');
        if (isMain && isLauncher) return activity['name']?.value;
      }
    }
    return null;
  }

  static int? _int(ManifestAttribute? attribute) {
    if (attribute == null) return null;
    return attribute.intValue ?? int.tryParse(attribute.value.trim());
  }

  static bool? _bool(ManifestAttribute? attribute) {
    if (attribute == null) return null;
    if (attribute.boolValue != null) return attribute.boolValue;
    return switch (attribute.value.trim().toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  }

  // Field numbers below are aapt2 Resources.proto: XmlNode, XmlElement,
  // XmlAttribute, Item, Reference and Primitive.
  static ManifestElement _element(ProtoMessage element) {
    final attributes = <String, ManifestAttribute>{};
    for (final attribute in element.messages(4)) {
      final name = attribute.string(2) ?? '';
      if (name.isEmpty) continue;
      final compiled = attribute.message(6);
      final reference = compiled?.message(1);
      final primitive = compiled?.message(7);
      attributes[name] = ManifestAttribute(
        name: name,
        value: attribute.string(3) ?? '',
        intValue: primitive?.varint(6)?.toSigned(32) ?? primitive?.varint(7),
        boolValue: primitive?.has(8) == true ? primitive!.varint(8) != 0 : null,
        referenceName: reference?.string(3),
      );
    }

    final children = <ManifestElement>[];
    for (final node in element.messages(5)) {
      final child = node.message(1);
      if (child != null) children.add(_element(child));
    }

    return ManifestElement(
      name: element.string(3) ?? '',
      attributes: attributes,
      children: children,
    );
  }
}

/// Permissions Android asks the user for at runtime. A new one showing up in
/// a release is worth a second look before it reaches everyone.
const dangerousPermissions = {
  'android.permission.ACCEPT_HANDOVER',
  'android.permission.ACCESS_BACKGROUND_LOCATION',
  'android.permission.ACCESS_COARSE_LOCATION',
  'android.permission.ACCESS_FINE_LOCATION',
  'android.permission.ACCESS_MEDIA_LOCATION',
  'android.permission.ACTIVITY_RECOGNITION',
  'android.permission.ADD_VOICEMAIL',
  'android.permission.ANSWER_PHONE_CALLS',
  'android.permission.BLUETOOTH_ADVERTISE',
  'android.permission.BLUETOOTH_CONNECT',
  'android.permission.BLUETOOTH_SCAN',
  'android.permission.BODY_SENSORS',
  'android.permission.BODY_SENSORS_BACKGROUND',
  'android.permission.CALL_PHONE',
  'android.permission.CAMERA',
  'android.permission.GET_ACCOUNTS',
  'android.permission.NEARBY_WIFI_DEVICES',
  'android.permission.POST_NOTIFICATIONS',
  'android.permission.PROCESS_OUTGOING_CALLS',
  'android.permission.READ_CALENDAR',
  'android.permission.READ_CALL_LOG',
  'android.permission.READ_CONTACTS',
  'android.permission.READ_EXTERNAL_STORAGE',
  'android.permission.READ_MEDIA_AUDIO',
  'android.permission.READ_MEDIA_IMAGES',
  'android.permission.READ_MEDIA_VIDEO',
  'android.permission.READ_MEDIA_VISUAL_USER_SELECTED',
  'android.permission.READ_PHONE_NUMBERS',
  'android.permission.READ_PHONE_STATE',
  'android.permission.READ_SMS',
  'android.permission.RECEIVE_MMS',
  'android.permission.RECEIVE_SMS',
  'android.permission.RECEIVE_WAP_PUSH',
  'android.permission.RECORD_AUDIO',
  'android.permission.SEND_SMS',
  'android.permission.USE_SIP',
  'android.permission.UWB_RANGING',
  'android.permission.WRITE_CALENDAR',
  'android.permission.WRITE_CALL_LOG',
  'android.permission.WRITE_CONTACTS',
  'android.permission.WRITE_EXTERNAL_STORAGE',
};
