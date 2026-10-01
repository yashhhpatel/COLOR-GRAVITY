"""Synthesizes all original Color Gravity audio (SFX + music loops).

Run:  python tool/gen_audio.py   (requires numpy; ffmpeg on PATH for .ogg)
Every sound is generated procedurally here, so the assets are 100% original.
"""
import os
import shutil
import subprocess
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')
TMP = os.path.join(os.path.dirname(__file__), '_wav')
os.makedirs(OUT, exist_ok=True)
os.makedirs(TMP, exist_ok=True)
rng = np.random.default_rng(7)
FFMPEG = os.environ.get('FFMPEG') or shutil.which('ffmpeg') or 'ffmpeg'


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def env(n, a=0.005, d=0.1, s=0.0, r=0.05, dur=None):
    """Simple ADSR envelope over n samples."""
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    sus_n = max(0, n - a_n - d_n - r_n)
    e = np.concatenate([
        np.linspace(0, 1, max(a_n, 1)),
        np.linspace(1, s, max(d_n, 1)),
        np.full(sus_n, s),
        np.linspace(s, 0, max(r_n, 1)),
    ])
    if len(e) < n:
        e = np.pad(e, (0, n - len(e)))
    return e[:n]


def sine(f, dur, phase=0.0):
    t = t_axis(dur)
    if np.isscalar(f):
        return np.sin(2 * np.pi * f * t + phase)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph + phase)


def tri(f, dur):
    t = t_axis(dur)
    if np.isscalar(f):
        ph = f * t
    else:
        ph = np.cumsum(f) / SR
    return 2 * np.abs(2 * (ph - np.floor(ph + 0.5))) - 1


def saw(f, dur):
    t = t_axis(dur)
    ph = f * t if np.isscalar(f) else np.cumsum(f) / SR
    return 2 * (ph - np.floor(ph + 0.5))


def square(f, dur, duty=0.5):
    t = t_axis(dur)
    ph = f * t if np.isscalar(f) else np.cumsum(f) / SR
    return np.where((ph % 1.0) < duty, 1.0, -1.0)


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def lowpass(x, cutoff):
    """One-pole low-pass; cutoff may be scalar or per-sample array."""
    y = np.zeros_like(x)
    c = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    alpha = 1 - np.exp(-2 * np.pi * c / SR)
    acc = 0.0
    for i in range(len(x)):
        acc += alpha[i] * (x[i] - acc)
        y[i] = acc
    return y


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def at(x, offset, total):
    out = np.zeros(total)
    start = int(offset * SR)
    end = min(total, start + len(x))
    if start < total:
        out[start:end] += x[:end - start]
    return out


def note(n):
    """MIDI note -> Hz."""
    return 440.0 * 2 ** ((n - 69) / 12)


def write(name, x, peak=0.85):
    x = np.asarray(x, dtype=float)
    m = np.max(np.abs(x)) or 1.0
    x = x / m * peak
    # tiny fades to avoid clicks
    f = min(64, len(x) // 4)
    x[:f] *= np.linspace(0, 1, f)
    x[-f:] *= np.linspace(1, 0, f)
    pcm = (x * 32767).astype(np.int16)
    wav_path = os.path.join(TMP, name + '.wav')
    with wave.open(wav_path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    ogg_path = os.path.join(OUT, name + '.ogg')
    subprocess.run([FFMPEG, '-y', '-loglevel', 'error', '-i', wav_path,
                    '-c:a', 'libvorbis', '-q:a', '3', ogg_path], check=True)
    print('wrote', ogg_path)


# ---------------------------------------------------------------- SFX
def sfx():
    # button: short soft click-blip
    d = 0.08
    write('button', sine(880, d) * env(int(SR * d), 0.002, 0.07) +
          0.3 * sine(1760, d) * env(int(SR * d), 0.001, 0.03))

    # move: airy short whoosh
    d = 0.18
    write('move', lowpass(noise(d), np.linspace(3000, 800, int(SR * d))) *
          env(int(SR * d), 0.03, 0.15), peak=0.5)

    # gravity shift: downward pitch sweep + whoosh
    d = 0.42
    n = int(SR * d)
    f = np.linspace(620, 140, n)
    body = tri(f, d) * env(n, 0.005, 0.38)
    whoosh = lowpass(noise(d), np.linspace(5000, 400, n)) * env(n, 0.06, 0.34) * 0.6
    write('gravity', mix(body, whoosh))

    # color change: bright quick arpeggio
    d = 0.3
    total = int(SR * d)
    parts = [at(sine(note(m), 0.12) * env(int(SR * 0.12), 0.002, 0.11), i * 0.05, total)
             for i, m in enumerate([76, 80, 83, 88])]
    write('color', mix(*parts))

    # collect: crisp pling
    d = 0.22
    n = int(SR * d)
    write('collect', (sine(note(84), d) + 0.4 * sine(note(96), d)) * env(n, 0.002, 0.2))

    # match: two-note confirm
    d = 0.28
    total = int(SR * d)
    write('match', mix(at(sine(note(79), 0.14) * env(int(SR * 0.14), 0.002, 0.13), 0, total),
                       at(sine(note(86), 0.16) * env(int(SR * 0.16), 0.002, 0.15), 0.08, total)))

    # merge: low thump + chime
    d = 0.5
    n = int(SR * d)
    thump = sine(np.linspace(180, 60, n), d) * env(n, 0.002, 0.2)
    chime = (sine(note(81), d) + 0.5 * sine(note(88), d) + 0.25 * sine(note(93), d)) * env(n, 0.01, 0.45) * 0.6
    write('merge', mix(thump, chime))

    # obstacle hit: low noisy crunch
    d = 0.35
    n = int(SR * d)
    crunch = lowpass(noise(d), 1200) * env(n, 0.001, 0.3)
    low = square(np.linspace(110, 45, n), d) * env(n, 0.001, 0.25) * 0.5
    write('hit', mix(crunch, low))

    # perfect: sparkle triad
    d = 0.5
    total = int(SR * d)
    parts = [at((sine(note(m), 0.3) + 0.3 * sine(note(m + 12), 0.3)) * env(int(SR * 0.3), 0.002, 0.28),
                i * 0.06, total) for i, m in enumerate([84, 88, 91, 96])]
    write('perfect', mix(*parts))

    # power-up: rising arpeggio with shimmer
    d = 0.6
    total = int(SR * d)
    parts = [at(square(note(m), 0.1, 0.3) * env(int(SR * 0.1), 0.002, 0.09) * 0.4, i * 0.06, total)
             for i, m in enumerate([67, 71, 74, 79, 83, 86, 91])]
    write('powerup', lowpass(mix(*parts), 5000))

    # coin / reward
    d = 0.3
    total = int(SR * d)
    write('coin', mix(at(square(note(88), 0.07, 0.25) * env(int(SR * 0.07), 0.001, 0.06), 0, total),
                      at(square(note(95), 0.2, 0.25) * env(int(SR * 0.2), 0.001, 0.19), 0.06, total)) * 0.5)

    # reward (bigger): chord bloom
    d = 0.8
    n = int(SR * d)
    chord = sum(sine(note(m), d) for m in [72, 76, 79, 84]) * env(n, 0.02, 0.7)
    write('reward', chord)

    # complete: fanfare
    d = 1.4
    total = int(SR * d)
    seq = [(72, 0.0), (76, 0.12), (79, 0.24), (84, 0.36)]
    parts = [at(saw(note(m), 0.5) * env(int(SR * 0.5), 0.005, 0.45) * 0.5, o, total) for m, o in seq]
    final = sum(saw(note(m), 0.9) for m in [72, 76, 79, 84]) * env(int(SR * 0.9), 0.01, 0.85) * 0.35
    write('complete', lowpass(mix(*parts, at(final, 0.5, total)), 4200))

    # fail: descending minor
    d = 1.0
    total = int(SR * d)
    seq = [(76, 0.0), (72, 0.18), (69, 0.36), (63, 0.54)]
    parts = [at(tri(note(m), 0.4) * env(int(SR * 0.4), 0.005, 0.38), o, total) for m, o in seq]
    write('fail', mix(*parts))

    # combo: quick upward blip
    d = 0.16
    n = int(SR * d)
    write('combo', square(np.linspace(600, 1400, n), d, 0.25) * env(n, 0.002, 0.15) * 0.5)

    # warning: two soft pulses (scripted gravity incoming)
    d = 0.4
    total = int(SR * d)
    p = sine(520, 0.1) * env(int(SR * 0.1), 0.005, 0.09)
    write('warning', mix(at(p, 0, total), at(p, 0.18, total)), peak=0.6)


# ---------------------------------------------------------------- MUSIC
def drum_kick():
    d = 0.25
    n = int(SR * d)
    return sine(np.linspace(140, 40, n), d) * env(n, 0.001, 0.22)


def drum_hat():
    d = 0.05
    return (noise(d) - lowpass(noise(d), 6000)) * env(int(SR * d), 0.001, 0.045) * 0.5


def drum_snare():
    d = 0.18
    n = int(SR * d)
    return (lowpass(noise(d), 4000) * 0.8 + sine(190, d) * 0.4) * env(n, 0.001, 0.16)


def music(name, bpm, progression, bars_per_chord, arp_pattern, drums, pad_level, arp_wave,
          bass_level=0.5, cutoff=2600, root=48):
    beat = 60.0 / bpm
    bars = len(progression) * bars_per_chord
    total_dur = bars * 4 * beat
    total = int(SR * total_dur)
    out = np.zeros(total)
    kick, hat, snare = drum_kick(), drum_hat(), drum_snare()
    for ci, chord in enumerate(progression):
        chord_start = ci * bars_per_chord * 4 * beat
        chord_len = bars_per_chord * 4 * beat
        notes = [root + c for c in chord]
        # pad
        pad = sum(saw(note(m + 12), chord_len) * 0.3 + sine(note(m + 12) * 1.003, chord_len) * 0.4
                  for m in notes)
        pad = lowpass(pad, 900) * env(int(SR * chord_len), 0.4, 0.2, 0.8, 0.4) * pad_level
        out += at(pad, chord_start, total)
        # bass
        if bass_level > 0:
            for b in range(bars_per_chord * 4):
                bn = sine(note(notes[0] - 12), beat * 0.9) + 0.4 * tri(note(notes[0] - 12), beat * 0.9)
                bn *= env(len(bn), 0.005, 0.3, 0.4, 0.1) * bass_level
                out += at(bn, chord_start + b * beat, total)
        # arp (16ths)
        step = beat / 4
        steps = int(chord_len / step)
        for s in range(steps):
            idx = arp_pattern[s % len(arp_pattern)]
            if idx is None:
                continue
            m = notes[idx % len(notes)] + 24 + 12 * (idx // len(notes))
            wave_fn = {'tri': tri, 'sq': lambda f, d: square(f, d, 0.3), 'sine': sine}[arp_wave]
            a = wave_fn(note(m), step * 1.6) * env(int(SR * step * 1.6), 0.003, step * 1.2) * 0.22
            out += at(a, chord_start + s * step, total)
    if drums:
        for b in range(bars * 4):
            t0 = b * beat
            if drums >= 1 and b % 1 == 0:
                out += at(kick * 0.7, t0, total)
            if drums >= 2:
                out += at(hat, t0 + beat / 2, total)
                if b % 2 == 1:
                    out += at(snare * 0.5, t0, total)
            if drums >= 3:
                out += at(hat * 0.6, t0 + beat / 4, total)
                out += at(hat * 0.6, t0 + 3 * beat / 4, total)
    out = lowpass(out, cutoff) * 0.6 + out * 0.4
    write(name, out, peak=0.7)


def all_music():
    # Chords as semitone offsets from root.
    I, vi, IV, V = [0, 4, 7], [9, 12, 16], [5, 9, 12], [7, 11, 14]
    i_m, VI, III, VII = [0, 3, 7], [8, 12, 15], [3, 7, 10], [10, 14, 17]
    music('music_home', 92, [I, vi, IV, V], 2, [0, None, 1, None, 2, None, 1, None], 0, 0.9, 'sine',
          bass_level=0.25, cutoff=1800)
    music('music_game_a', 118, [I, V, vi, IV], 2, [0, 1, 2, 3, 2, 1, 0, 1], 2, 0.55, 'tri')
    music('music_game_b', 124, [i_m, VI, III, VII], 2, [0, 2, 1, 3, 0, 2, 4, 2], 3, 0.5, 'sq', cutoff=2200)
    music('music_game_c', 110, [vi, IV, I, V], 2, [0, None, 2, 1, None, 3, 2, None], 2, 0.6, 'tri',
          root=50)


if __name__ == '__main__':
    sfx()
    all_music()
