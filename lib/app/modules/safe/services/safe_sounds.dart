import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The safe's sound effects, made by tool/generate_safe_sounds.dart.
enum SafeSound { tick, denied, unlock, lock }

/// Where sounds go, behind a seam: the tests swap in a recorder.
abstract interface class SafeSoundOutput {
  /// Loads the sounds ahead of the first one, so it plays without delay.
  Future<void> prepare();
  Future<void> play(SafeSound sound);
}

class SilentSafeSoundOutput implements SafeSoundOutput {
  const SilentSafeSoundOutput();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> play(SafeSound sound) async {}
}

/// Plays through audioplayers on Windows and macOS.
///
/// Each sound sits loaded in a player of its own and is rewound to play
/// again, so a key click does not wait for a file to open. Ticks rotate
/// through several players and three pitches, so fast typing overlaps
/// instead of cutting each click off, and does not sound like a machine.
class AudioplayersSafeSoundOutput implements SafeSoundOutput {
  AudioplayersSafeSoundOutput({this.volume = 0.8});

  final double volume;

  static const _tickVariants = 3;
  static const _tickCopies = 2;

  final _players = <String, AudioPlayer>{};
  Future<void>? _ready;
  int _ticks = 0;

  @override
  Future<void> prepare() => _ready ??= _load();

  Future<void> _load() async {
    Future<void> load(String key, String file) async {
      final player = AudioPlayer(playerId: 'amc-safe-$key');
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(volume);
      await player.setSource(AssetSource('sounds/safe/$file.wav'));
      _players[key] = player;
    }

    for (var variant = 1; variant <= _tickVariants; variant++) {
      for (var copy = 0; copy < _tickCopies; copy++) {
        await load('tick_${variant}_$copy', 'tick_$variant');
      }
    }
    for (final sound in [SafeSound.denied, SafeSound.unlock, SafeSound.lock]) {
      await load(sound.name, sound.name);
    }
  }

  @override
  Future<void> play(SafeSound sound) async {
    await prepare();
    final String key;
    if (sound == SafeSound.tick) {
      final n = _ticks++;
      key =
          'tick_${n % _tickVariants + 1}_${(n ~/ _tickVariants) % _tickCopies}';
    } else {
      key = sound.name;
    }
    final player = _players[key];
    if (player == null) return;
    await player.stop();
    await player.resume();
  }
}

/// The safe's sounds and whether they are on.
///
/// The switch is kept in shared preferences rather than in the safe's own
/// settings: those are sealed inside the safe, and the door has to know
/// whether to click before it has been opened.
class SafeSounds extends ChangeNotifier {
  SafeSounds({
    SafeSoundOutput? output,
    Future<SharedPreferences?> Function()? preferences,
  }) : _output = output ?? AudioplayersSafeSoundOutput(),
       _preferences = preferences ?? SharedPreferences.getInstance;

  static SafeSounds? _shared;

  /// The app-wide sounds. Silent under `flutter test`, which has no audio
  /// plugin and no preferences behind its channels.
  static SafeSounds get shared => _shared ??= _runningUnderTest
      ? SafeSounds(
          output: const SilentSafeSoundOutput(),
          preferences: () async => null,
        )
      : SafeSounds();

  static bool get _runningUnderTest =>
      Platform.environment.containsKey('FLUTTER_TEST');

  static const _enabledKey = 'safe_sounds_enabled';

  final SafeSoundOutput _output;
  final Future<SharedPreferences?> Function() _preferences;

  bool _enabled = true;
  bool get enabled => _enabled;

  bool _loaded = false;

  /// After one failure the output is left alone, so a missing audio device
  /// is reported once rather than on every keystroke.
  bool _broken = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      _enabled = (await _preferences())?.getBool(_enabledKey) ?? true;
    } catch (error) {
      debugPrint('Could not read the safe sound setting: $error');
    }
    notifyListeners();
    if (_enabled) _warmUp();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    if (value) _warmUp();
    try {
      await (await _preferences())?.setBool(_enabledKey, value);
    } catch (error) {
      debugPrint('Could not save the safe sound setting: $error');
    }
  }

  void play(SafeSound sound) {
    if (!_enabled || _broken) return;
    unawaited(_output.play(sound).catchError(_fail));
  }

  void _warmUp() {
    if (_broken) return;
    unawaited(_output.prepare().catchError(_fail));
  }

  void _fail(Object error) {
    _broken = true;
    debugPrint('Safe sounds are off: $error');
  }
}
