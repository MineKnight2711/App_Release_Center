class ReleaseFastlaneLane {
  const ReleaseFastlaneLane({
    required this.name,
    this.platform,
    this.description,
  });

  final String name;
  final String? platform;
  final String? description;

  String get key => 'fastlane:${platform ?? 'default'}:$name';

  String get label {
    return name
        .split(RegExp(r'[_-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String get summary {
    final trimmed = description?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return 'Runs this Fastlane lane.';
  }

  String get command {
    final target = platform == null ? name : '$platform $name';
    return 'fastlane $target';
  }
}
