import 'dart:math';

/// What the generator may draw from.
class PasswordRecipe {
  const PasswordRecipe({
    this.length = 20,
    this.upper = true,
    this.lower = true,
    this.digits = true,
    this.symbols = true,
    this.avoidLookalikes = true,
  });

  final int length;
  final bool upper;
  final bool lower;
  final bool digits;
  final bool symbols;

  /// Leaves out `Il1O0` so a password read off a screen is typed right.
  final bool avoidLookalikes;

  PasswordRecipe copyWith({
    int? length,
    bool? upper,
    bool? lower,
    bool? digits,
    bool? symbols,
    bool? avoidLookalikes,
  }) => PasswordRecipe(
    length: length ?? this.length,
    upper: upper ?? this.upper,
    lower: lower ?? this.lower,
    digits: digits ?? this.digits,
    symbols: symbols ?? this.symbols,
    avoidLookalikes: avoidLookalikes ?? this.avoidLookalikes,
  );

  List<String> get groups {
    String strip(String value) =>
        avoidLookalikes ? value.replaceAll(RegExp('[Il1O0o]'), '') : value;
    return [
      if (upper) strip('ABCDEFGHIJKLMNOPQRSTUVWXYZ'),
      if (lower) strip('abcdefghijklmnopqrstuvwxyz'),
      if (digits) strip('0123456789'),
      if (symbols) '!@#\$%^&*()-_=+[]{};:,.?/~',
    ];
  }
}

/// Draws a password from [recipe] with a cryptographic RNG, one character
/// from every chosen group so a site's "must contain a digit" rule is met.
String generatePassword(PasswordRecipe recipe, {Random? random}) {
  final rng = random ?? Random.secure();
  final groups = recipe.groups;
  if (groups.isEmpty) return '';
  final pool = groups.join();
  final length = max(recipe.length, groups.length);
  final chars = <String>[
    for (final group in groups) group[rng.nextInt(group.length)],
    for (var i = groups.length; i < length; i++) pool[rng.nextInt(pool.length)],
  ];
  // Fisher–Yates, so the guaranteed characters are not always up front.
  for (var i = chars.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final swap = chars[i];
    chars[i] = chars[j];
    chars[j] = swap;
  }
  return chars.join();
}

enum PasswordStrength {
  empty('Chưa nhập', 0),
  weak('Yếu', 1),
  fair('Tạm được', 2),
  good('Khá', 3),
  strong('Mạnh', 4);

  const PasswordStrength(this.label, this.level);

  final String label;
  final int level;
}

/// A rough entropy estimate from length and character variety, with a
/// penalty for runs and repeats. It is a nudge, not an audit.
PasswordStrength ratePassword(String value) {
  if (value.isEmpty) return PasswordStrength.empty;
  var poolSize = 0;
  if (RegExp('[a-z]').hasMatch(value)) poolSize += 26;
  if (RegExp('[A-Z]').hasMatch(value)) poolSize += 26;
  if (RegExp('[0-9]').hasMatch(value)) poolSize += 10;
  if (RegExp('[^a-zA-Z0-9]').hasMatch(value)) poolSize += 32;
  final unique = value.split('').toSet().length;
  final effectiveLength = min(value.length, unique * 2);
  final bits = effectiveLength * (log(max(poolSize, 1)) / ln2);
  if (bits < 36) return PasswordStrength.weak;
  if (bits < 60) return PasswordStrength.fair;
  if (bits < 90) return PasswordStrength.good;
  return PasswordStrength.strong;
}
