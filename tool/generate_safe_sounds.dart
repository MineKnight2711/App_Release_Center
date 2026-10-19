// Synthesizes the safe's sound effects into assets/sounds/safe/.
//
//   dart run tool/generate_safe_sounds.dart
//
// Every sound is built from scratch, no recordings: damped inharmonic
// partials for metal, pitch-dropping sines for heavy thuds, filtered noise
// for air and friction. The timings follow the door animation in
// lib/app/modules/safe/views/safe_door.dart (SafeOpening), so the bolts are
// heard when they are seen. The random seed is fixed: running the script
// again produces the same files. Replace any WAV with a recording of the
// same name to change a sound.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const rate = 44100;
final _random = Random(20261019);

void main() {
  final out = Directory('assets/sounds/safe')..createSync(recursive: true);
  final sounds = {
    for (final (index, pitch) in [(1, 1.0), (2, 0.93), (3, 1.07)].indexed)
      'tick_${index + 1}': (tick(pitch.$2), 0.42),
    'denied': (denied(), 0.62),
    'unlock': (unlock(), 0.8),
    'lock': (lock(), 0.85),
  };
  for (final entry in sounds.entries) {
    final (samples, peak) = entry.value;
    final file = File('${out.path}/${entry.key}.wav');
    file.writeAsBytesSync(wav(normalize(samples, peak)));
    stdout.writeln(
      '${file.path}  ${(samples.length / rate * 1000).round()} ms',
    );
  }
}

// ---- the sounds -------------------------------------------------------

/// One click of the dial as a character is typed.
Float64List tick(double pitch) {
  final mix = Mix(0.07);
  mix.add(noiseBurst(0.004, decay: 0.0015, band: (5200 * pitch, 1.2)), 0);
  mix.add(
    modal(
      2100 * pitch,
      const [1, 2.4, 3.9],
      const [0.010, 0.006, 0.004],
      const [1, 0.5, 0.3],
      0.06,
    ),
    0,
    gain: 0.5,
  );
  mix.add(
    modal(650 * pitch, const [1], const [0.006], const [1], 0.04),
    0,
    gain: 0.35,
  );
  return mix.samples;
}

/// A locked handle jiggled three times, then a low two-pulse buzzer.
Float64List denied() {
  final mix = Mix(0.75);
  for (final (at, gain) in [(0.0, 1.0), (0.085, 0.8), (0.16, 0.65)]) {
    mix.add(
      knock(520 * (1 + (_random.nextDouble() - 0.5) * 0.04)),
      at,
      gain: gain,
    );
  }
  mix.add(buzz(155, 0.16), 0.26, gain: 0.6);
  mix.add(buzz(155, 0.20), 0.47, gain: 0.6);
  return mix.samples;
}

/// The door opening, 1.5 s, in step with the opening animation: latch at
/// once, the handle's ratchet over 0–330 ms, bolts drawn back around 250
/// and 420 ms, the door swinging from 450 ms, settling at about 1.17 s.
Float64List unlock() {
  final mix = Mix(1.6);
  mix.add(noiseBurst(0.004, decay: 0.0015, band: (5000, 1.2)), 0, gain: 0.5);
  mix.add(
    modal(1400, const [1, 2.3], const [0.02, 0.01], const [1, 0.5], 0.08),
    0,
    gain: 0.35,
  );
  mix.add(thump(140, 90, decay: 0.07, duration: 0.25), 0.05, gain: 0.6);
  mix.add(noiseBurst(0.06, decay: 0.03, lowpass: 900), 0.05, gain: 0.4);

  // The handle: a ratchet whose clicks speed up as it turns, over friction.
  for (var k = 0; k < 8; k++) {
    final at = 0.06 + 0.27 * pow(k / 7, 0.8);
    mix.add(
      modal(
        1800 * (0.95 + 0.1 * _random.nextDouble()),
        const [1, 2.6],
        const [0.006, 0.004],
        const [1, 0.5],
        0.03,
      ),
      at.toDouble(),
      gain: 0.25,
    );
  }
  mix.add(friction(0.27), 0.06, gain: 0.08);

  mix.add(boltClank(1.0), 0.25, gain: 0.55);
  mix.add(boltClank(0.94), 0.42, gain: 0.55);

  mix.add(whoosh(0.75, low: 150, high: 450), 0.45, gain: 0.6);
  mix.add(creak(0.55), 0.5, gain: 0.28);
  mix.add(thump(70, 55, decay: 0.08, duration: 0.3), 1.17, gain: 0.3);
  return mix.samples;
}

/// The door shutting, in step with the 900 ms closing animation: it swings
/// shut by about 630 ms, the bolts are thrown around 680 and 780 ms, and
/// the dial spins back as the handle returns.
Float64List lock() {
  final mix = Mix(1.25);
  mix.add(whoosh(0.42, low: 180, high: 520), 0.2, gain: 1.1);
  mix.add(creak(0.3), 0.25, gain: 0.32);

  // The slam: a heavy low thud, a burst of air, the body ringing a little.
  mix.add(thump(75, 45, decay: 0.16, duration: 0.5), 0.63, gain: 1.0);
  mix.add(noiseBurst(0.12, decay: 0.035, lowpass: 700), 0.63, gain: 0.6);
  mix.add(
    modal(220, const [1, 2.76, 5.4], const [0.25, 0.12, 0.06], const [
      0.5,
      0.3,
      0.15,
    ], 0.6),
    0.63,
    gain: 0.35,
  );

  mix.add(boltClank(1.05), 0.68, gain: 0.5);
  mix.add(boltClank(1.0), 0.78, gain: 0.5);

  for (var k = 0; k < 6; k++) {
    mix.add(tick(0.9 + 0.04 * k), 0.84 + 0.03 * k, gain: 0.5 - 0.06 * k);
  }
  return mix.samples;
}

// ---- building blocks ----------------------------------------------------

/// A metal knock: a bar's inharmonic partials over a short noise click.
Float64List knock(double freq) {
  final mix = Mix(0.15);
  mix.add(
    modal(freq, const [1, 2.76, 5.40], const [0.05, 0.03, 0.015], const [
      1,
      0.6,
      0.35,
    ], 0.15),
    0,
  );
  mix.add(noiseBurst(0.01, decay: 0.004, band: (2500, 1.5)), 0, gain: 0.5);
  return mix.samples;
}

/// A heavy bolt sliding home: low thud, clanking steel, a scrape of noise.
Float64List boltClank(double pitch) {
  final mix = Mix(0.4);
  mix.add(
    modal(
      310 * pitch,
      const [1, 2.76, 5.40, 8.93],
      const [0.12, 0.07, 0.04, 0.02],
      const [1, 0.6, 0.35, 0.2],
      0.4,
    ),
    0,
  );
  mix.add(
    thump(95 * pitch, 60 * pitch, decay: 0.1, duration: 0.35),
    0,
    gain: 1.3,
  );
  mix.add(noiseBurst(0.04, decay: 0.012, lowpass: 1500), 0, gain: 0.6);
  return mix.samples;
}

/// Damped sinusoids at [ratios] of [freq]: the modes of a struck object.
Float64List modal(
  double freq,
  List<double> ratios,
  List<double> decays,
  List<double> amps,
  double duration,
) {
  final out = Float64List((duration * rate).round());
  for (var m = 0; m < ratios.length; m++) {
    final f = freq * ratios[m];
    final phase = _random.nextDouble() * 2 * pi;
    for (var i = 0; i < out.length; i++) {
      final t = i / rate;
      out[i] += amps[m] * exp(-t / decays[m]) * sin(2 * pi * f * t + phase);
    }
  }
  return _attack(out, 0.0005);
}

/// A sine falling from [from] to [to] Hz: the body of a heavy thud.
Float64List thump(
  double from,
  double to, {
  required double decay,
  required double duration,
}) {
  final out = Float64List((duration * rate).round());
  var phase = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / rate;
    final f = to + (from - to) * exp(-t / (decay * 0.6));
    phase += 2 * pi * f / rate;
    out[i] = sin(phase) * exp(-t / decay);
  }
  return _attack(out, 0.002);
}

/// White noise with a fast decay, optionally filtered.
Float64List noiseBurst(
  double duration, {
  required double decay,
  double? lowpass,
  (double, double)? band,
}) {
  final out = Float64List((duration * rate).round());
  for (var i = 0; i < out.length; i++) {
    out[i] = (_random.nextDouble() * 2 - 1) * exp(-(i / rate) / decay);
  }
  if (lowpass != null) Biquad.lowpass(lowpass, 0.707).process(out);
  if (band != null) Biquad.bandpass(band.$1, band.$2).process(out);
  return _attack(out, 0.0003);
}

/// A low buzzer: odd harmonics of [freq], soft-clipped and rounded off.
Float64List buzz(double freq, double duration) {
  final out = Float64List((duration * rate).round());
  for (var i = 0; i < out.length; i++) {
    final t = i / rate;
    var value = 0.0;
    for (var h = 1; h <= 11; h += 2) {
      value += sin(2 * pi * freq * h * t) / h;
    }
    final envelope = min(1.0, t / 0.005) * min(1.0, (duration - t) / 0.02);
    out[i] = _softClip(value * 1.4) * envelope;
  }
  Biquad.lowpass(1800, 0.707).process(out);
  return out;
}

/// Noise swept through a lowpass that opens and closes: air moved by a
/// heavy door.
Float64List whoosh(
  double duration, {
  required double low,
  required double high,
}) {
  final out = Float64List((duration * rate).round());
  final filter = Biquad.lowpass(low, 0.8);
  for (var i = 0; i < out.length; i++) {
    final x = i / out.length;
    final shape = sin(pi * x);
    if (i % 64 == 0) filter.setLowpass(low + (high - low) * shape, 0.8);
    out[i] = filter.step((_random.nextDouble() * 2 - 1)) * shape;
  }
  return out;
}

/// A hinge: stick-slip impulses at a wandering rate, ringing through a
/// few resonances.
Float64List creak(double duration) {
  final out = Float64List((duration * rate).round());
  var next = 0.0;
  for (var i = 0; i < out.length; i++) {
    final x = i / out.length;
    if (i >= next) {
      out[i] = 1.0;
      final hz = 70 + 90 * sin(pi * x) + 25 * (_random.nextDouble() - 0.5);
      next = i + rate / hz;
    }
  }
  final mixed = Float64List(out.length);
  for (final (f, q, g) in [
    (720.0, 9.0, 1.0),
    (1480.0, 8.0, 0.6),
    (2650.0, 7.0, 0.3),
  ]) {
    final band = Float64List.fromList(out);
    Biquad.bandpass(f, q).process(band);
    for (var i = 0; i < band.length; i++) {
      mixed[i] += band[i] * g;
    }
  }
  for (var i = 0; i < mixed.length; i++) {
    mixed[i] *= sin(pi * i / mixed.length);
  }
  return mixed;
}

/// Band-limited noise under a turning handle.
Float64List friction(double duration) {
  final out = Float64List((duration * rate).round());
  for (var i = 0; i < out.length; i++) {
    out[i] = (_random.nextDouble() * 2 - 1) * sin(pi * i / out.length);
  }
  Biquad.bandpass(1200, 2).process(out);
  return out;
}

double _softClip(double x) => x / (1 + x.abs());

/// Ramps the first [seconds] up from silence, so no sound starts on a click.
Float64List _attack(Float64List samples, double seconds) {
  final n = min(samples.length, (seconds * rate).round());
  for (var i = 0; i < n; i++) {
    samples[i] *= i / n;
  }
  return samples;
}

class Mix {
  Mix(double seconds) : samples = Float64List((seconds * rate).round());

  final Float64List samples;

  void add(Float64List sound, double at, {double gain = 1}) {
    final offset = (at * rate).round();
    for (var i = 0; i < sound.length && offset + i < samples.length; i++) {
      samples[offset + i] += sound[i] * gain;
    }
  }
}

/// RBJ cookbook biquad.
class Biquad {
  Biquad._();

  factory Biquad.lowpass(double freq, double q) =>
      Biquad._()..setLowpass(freq, q);

  factory Biquad.bandpass(double freq, double q) {
    final filter = Biquad._();
    final w = 2 * pi * freq / rate;
    final alpha = sin(w) / (2 * q);
    filter._set(alpha, 0, -alpha, 1 + alpha, -2 * cos(w), 1 - alpha);
    return filter;
  }

  double _b0 = 0, _b1 = 0, _b2 = 0, _a1 = 0, _a2 = 0;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  void setLowpass(double freq, double q) {
    final w = 2 * pi * freq / rate;
    final alpha = sin(w) / (2 * q);
    final c = cos(w);
    _set((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + alpha, -2 * c, 1 - alpha);
  }

  void _set(double b0, double b1, double b2, double a0, double a1, double a2) {
    _b0 = b0 / a0;
    _b1 = b1 / a0;
    _b2 = b2 / a0;
    _a1 = a1 / a0;
    _a2 = a2 / a0;
  }

  double step(double x) {
    final y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }

  void process(Float64List samples) {
    for (var i = 0; i < samples.length; i++) {
      samples[i] = step(samples[i]);
    }
  }
}

/// Scales to [peak] and fades the last 10 ms, so nothing ends on a click.
Float64List normalize(Float64List samples, double peak) {
  var max = 0.0;
  for (final s in samples) {
    if (s.abs() > max) max = s.abs();
  }
  final scale = max == 0 ? 1.0 : peak / max;
  final fade = (0.01 * rate).round();
  for (var i = 0; i < samples.length; i++) {
    final tail = samples.length - i;
    samples[i] *= scale * (tail < fade ? tail / fade : 1);
  }
  return samples;
}

/// 16-bit mono PCM WAV.
Uint8List wav(Float64List samples) {
  final data = ByteData(44 + samples.length * 2);
  void ascii(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      data.setUint8(at + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final value = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    data.setInt16(44 + i * 2, value, Endian.little);
  }
  return data.buffer.asUint8List();
}
