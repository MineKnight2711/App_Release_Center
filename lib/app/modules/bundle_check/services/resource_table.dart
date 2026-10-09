import 'dart:typed_data';

import 'proto_reader.dart';

/// Reads string values out of an AAB's `resources.pb` (aapt2 ResourceTable).
///
/// Only the default-configuration value is taken: `values/strings.xml`, not
/// `values-vi/strings.xml`. Firebase and API keys never vary by locale, and
/// taking the default keeps two configurations from disagreeing silently.
Map<String, String> readStringResources(
  Uint8List data, {
  required Set<String> names,
}) {
  final found = <String, String>{};
  if (names.isEmpty) return found;

  final table = ProtoMessage.parse(data);
  // ResourceTable.package = 2 → Package.type = 3 → Type.name = 2,
  // Type.entry = 3 → Entry.name = 2, Entry.config_value = 6 →
  // ConfigValue.config = 1, ConfigValue.value = 2 → Value.item = 4.
  for (final package in table.messages(2)) {
    for (final type in package.messages(3)) {
      if (type.string(2) != 'string') continue;
      for (final entry in type.messages(3)) {
        final name = entry.string(2);
        if (name == null || !names.contains(name)) continue;
        String? fallback;
        for (final configValue in entry.messages(6)) {
          final text = _itemText(configValue.message(2)?.message(4));
          if (text == null) continue;
          final config = configValue.first(1);
          if (config == null || config.bytes.isEmpty) {
            found[name] = text;
            fallback = null;
            break;
          }
          fallback ??= text;
        }
        if (fallback != null) found.putIfAbsent(name, () => fallback!);
      }
    }
  }
  return found;
}

// Item.str = 2, Item.raw_str = 3, Item.styled_str = 4; each keeps its text
// in field 1.
String? _itemText(ProtoMessage? item) {
  if (item == null) return null;
  for (final field in const [2, 3, 4]) {
    final value = item.message(field)?.string(1);
    if (value != null) return value;
  }
  return null;
}
