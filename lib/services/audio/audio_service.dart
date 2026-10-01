import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../settings/settings_controller.dart';

enum Sfx {
  button('button'),
  move('move'),
  gravity('gravity'),
  color('color'),
  collect('collect'),
  match('match'),
  merge('merge'),
  hit('hit'),
  perfect('perfect'),
  powerUp('powerup'),
  coin('coin'),
  reward('reward'),
  complete('complete'),
  fail('fail'),
  combo('combo'),
  warning('warning');

  const Sfx(this.file);
  final String file;
}

enum MusicTrack {
  home('music_home'),
  gameA('music_game_a'),
  gameB('music_game_b'),
  gameC('music_game_c');

  const MusicTrack(this.file);
  final String file;

  static MusicTrack forWorld(int musicIndex) => [gameA, gameB, gameC][musicIndex % 3];
}

/// Sound effects + looping music. All sounds are original procedurally
/// generated assets (see tool/gen_audio.py).
abstract class AudioService {
  Future<void> init();
  void play(Sfx s, {double volume = 1});
  void playMusic(MusicTrack t);
  void stopMusic();
  void pauseAll();
  void resumeAll();
}

class SilentAudioService implements AudioService {
  @override
  Future<void> init() async {}
  @override
  void play(Sfx s, {double volume = 1}) {}
  @override
  void playMusic(MusicTrack t) {}
  @override
  void stopMusic() {}
  @override
  void pauseAll() {}
  @override
  void resumeAll() {}
}

class GameAudioService implements AudioService {
  GameAudioService(this.settings) {
    settings.addListener(_onSettings);
  }

  final SettingsController settings;
  final Map<Sfx, AudioPool> _pools = {};
  final AudioPlayer _music = AudioPlayer(playerId: 'music');
  MusicTrack? _track;
  bool _paused = false;
  bool _ready = false;
  final Map<Sfx, int> _lastPlayed = {};

  @override
  Future<void> init() async {
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
      );
      await _music.setReleaseMode(ReleaseMode.loop);
      await _music.setVolume(0.42);
      for (final s in Sfx.values) {
        _pools[s] = await AudioPool.createFromAsset(
          path: 'audio/${s.file}.ogg',
          maxPlayers: s == Sfx.coin || s == Sfx.collect ? 4 : 2,
        );
      }
      _ready = true;
    } catch (e) {
      debugPrint('Audio unavailable: $e');
    }
  }

  @override
  void play(Sfx s, {double volume = 1}) {
    if (!_ready || !settings.sfx || _paused) return;
    // Rate-limit identical sounds so bursts stay clean.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (_lastPlayed[s] ?? 0) < 45) return;
    _lastPlayed[s] = now;
    final pool = _pools[s];
    if (pool == null) return;
    pool.start(volume: volume).then((_) {}, onError: (Object _) {});
  }

  @override
  void playMusic(MusicTrack t) {
    if (_track == t && _music.state == PlayerState.playing) return;
    _track = t;
    _applyMusic();
  }

  Future<void> _applyMusic() async {
    try {
      if (!settings.music || _track == null || _paused) {
        await _music.pause();
        return;
      }
      await _music.stop();
      await _music.play(AssetSource('audio/${_track!.file}.ogg'));
    } catch (e) {
      debugPrint('Music error: $e');
    }
  }

  @override
  void stopMusic() {
    _track = null;
    _music.stop().catchError((_) {});
  }

  @override
  void pauseAll() {
    _paused = true;
    _music.pause().catchError((_) {});
  }

  @override
  void resumeAll() {
    _paused = false;
    if (settings.music && _track != null) _music.resume().catchError((_) {});
  }

  bool _lastMusic = true;
  void _onSettings() {
    if (settings.music != _lastMusic) {
      _lastMusic = settings.music;
      if (settings.music) {
        _applyMusic();
      } else {
        _music.pause().catchError((_) {});
      }
    }
  }
}
