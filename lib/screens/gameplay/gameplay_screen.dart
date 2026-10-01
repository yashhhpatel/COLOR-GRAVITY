import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/constants/app_config.dart';
import '../../core/constants/game_constants.dart';
import '../../core/models/gravity_dir.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/world_themes.dart';
import '../../game/engine/game_engine.dart';
import '../../game/render/game_painter.dart';
import '../../levels/generators/level_generator.dart';
import '../../levels/models/level_config.dart';
import '../../progression/progress_controller.dart';
import '../../services/app_services.dart';
import '../../services/audio/audio_service.dart';
import '../../services/haptics/haptics_service.dart';
import '../../widgets/common/ui.dart';
import '../failure/failure_screen.dart';
import '../home/home_screen.dart';
import '../result/result_screen.dart';
import 'hud.dart';

class RunRequest {
  const RunRequest.level(this.level, {this.withShield = false, this.resume})
      : kind = RunKind.level,
        seed = 0;
  const RunRequest.daily()
      : kind = RunKind.daily,
        level = 0,
        withShield = false,
        resume = null,
        seed = 0;
  const RunRequest.endless({this.seed = 0})
      : kind = RunKind.endless,
        level = 0,
        withShield = false,
        resume = null;

  final RunKind kind;
  final int level;
  final bool withShield;
  final int seed;

  /// Resume a Hard / Very Hard level from its checkpoint.
  final CheckpointState? resume;
}

class GameplayScreen extends StatefulWidget {
  const GameplayScreen({super.key, required this.request});
  final RunRequest request;

  /// The engine of the most recently started run (integration tests only).
  @visibleForTesting
  static GameEngine? debugEngine;

  @override
  State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen> with SingleTickerProviderStateMixin {
  late final AppServices _s = AppScope.of(context);
  late final LoadedLevel _level;
  late final GameEngine _engine;
  late final Ticker _ticker;
  late final GamePainter _painter;
  Duration _last = Duration.zero;
  bool _started = false;
  bool _introVisible = true;
  bool _paused = false;
  bool _showResult = false;
  bool _showFailure = false;
  bool _recorded = false;
  bool _continueUsed = false;
  RunReward? _reward;
  int? _prevEndlessBest;

  // Coins flying into the HUD counter.
  final GlobalKey _coinKey = GlobalKey();
  final ValueNotifier<int> _coinBump = ValueNotifier(0);
  final List<(int, Offset, Offset)> _flyers = [];
  int _flyerId = 0;
  Size _size = Size.zero;

  // Gesture tracking
  Offset _panTotal = Offset.zero;
  DateTime _panStart = DateTime.now();

  RunKind get _kind => widget.request.kind;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _level = switch (_kind) {
      RunKind.level => LevelGenerator.load(widget.request.level),
      RunKind.daily => LevelGenerator.daily(DateTime.now()),
      RunKind.endless =>
        LevelGenerator.endless(widget.request.seed == 0 ? DateTime.now().millisecondsSinceEpoch & 0xFFFFFF : widget.request.seed),
    };
    _engine = GameEngine(level: _level, loadout: _s.progress.loadout, resume: widget.request.resume);
    if (widget.request.withShield) _engine.player.shield = true;
    GameplayScreen.debugEngine = _engine;
    _prevEndlessBest = _s.progress.data.endlessBestScore;
    _painter = GamePainter(_engine);
    _ticker = createTicker(_onTick)..start();
    final theme = WorldTheme.byId(_level.config.worldId);
    _s.audio.playMusic(MusicTrack.forWorld(theme.musicTrack));
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _introVisible = false);
    });
  }

  void _onTick(Duration now) {
    final dt = _last == Duration.zero ? 0.0 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (_introVisible || _paused) {
      _engine.update(0);
      return;
    }
    _engine.update(dt);
    for (final ev in _engine.drainEvents()) {
      _handle(ev);
    }
  }

  void _handle(GameEvent ev) {
    final a = _s.audio, h = _s.haptics;
    switch (ev.type) {
      case GameEventType.gravityShift:
        a.play(Sfx.gravity, volume: ev.value == 1 ? 0.8 : 1);
        h.fire(Haptic.light);
      case GameEventType.gravityWarning:
        a.play(Sfx.warning);
      case GameEventType.gravityLocked:
        h.fire(Haptic.selection);
      case GameEventType.colorChange:
        a.play(Sfx.color);
        h.fire(Haptic.selection);
      case GameEventType.collect:
        a.play(Sfx.collect, volume: 0.75);
      case GameEventType.mismatch:
        a.play(Sfx.move, volume: 0.6);
        h.fire(Haptic.selection);
      case GameEventType.checkpoint:
        a.play(Sfx.perfect);
        h.fire(Haptic.medium);
      case GameEventType.coin:
        _flyCoin(ev);
        a.play(Sfx.coin, volume: 0.5);
      case GameEventType.merge:
        a.play(Sfx.merge);
        h.fire(ev.value >= 4 ? Haptic.heavy : Haptic.medium);
      case GameEventType.hit:
        a.play(Sfx.hit);
        h.fire(Haptic.heavy);
      case GameEventType.shieldBlock:
        a.play(Sfx.hit, volume: 0.5);
        h.fire(Haptic.medium);
      case GameEventType.perfect:
        a.play(Sfx.perfect, volume: 0.7);
        h.fire(Haptic.light);
      case GameEventType.powerUp:
        a.play(Sfx.powerUp);
        h.fire(Haptic.medium);
      case GameEventType.gatePass:
        a.play(Sfx.match, volume: 0.8);
      case GameEventType.combo:
        a.play(Sfx.combo, volume: 0.6);
      case GameEventType.delivery:
        a.play(Sfx.match);
        h.fire(Haptic.light);
      case GameEventType.bomb:
        a.play(Sfx.hit);
        h.fire(Haptic.heavy);
      case GameEventType.tutorialDone:
        a.play(Sfx.perfect, volume: 0.6);
        h.fire(Haptic.light);
      case GameEventType.complete:
        a.play(Sfx.complete);
        h.fire(Haptic.heavy);
        Future.delayed(const Duration(milliseconds: 1100), _onComplete);
      case GameEventType.fail:
        a.play(Sfx.fail);
        h.fire(Haptic.heavy);
        Future.delayed(const Duration(milliseconds: 750), () {
          if (mounted && _engine.phase == RunPhase.failed) setState(() => _showFailure = true);
        });
    }
  }

  void _onComplete() {
    if (!mounted) return;
    final c = _level.config;
    final p = _s.progress;
    final reward = switch (_kind) {
      RunKind.level =>
        p.recordLevel(level: c.levelId, completed: true, stars: _engine.stars, stats: _engine.stats, baseReward: c.baseReward),
      RunKind.daily => p.recordDaily(completed: true, stats: _engine.stats),
      RunKind.endless => p.recordEndless(_engine.stats),
    };
    _recorded = true;
    _s.audio.play(Sfx.reward, volume: 0.6);
    setState(() {
      _reward = reward;
      _showResult = true;
    });
  }

  /// Failed runs are recorded when the player leaves (so continue can resume).
  void _recordFailureOnce() {
    if (_recorded) return;
    _recorded = true;
    final c = _level.config;
    final p = _s.progress;
    switch (_kind) {
      case RunKind.level:
        p.recordLevel(level: c.levelId, completed: false, stars: 0, stats: _engine.stats, baseReward: c.baseReward);
      case RunKind.daily:
        p.recordDaily(completed: false, stats: _engine.stats);
      case RunKind.endless:
        p.recordEndless(_engine.stats);
    }
  }

  void _flyCoin(GameEvent ev) {
    if (_flyers.length >= 10 || _size == Size.zero) return;
    final box = _coinKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final t = ArenaTransform(_size);
    final from = t.offset + Offset(ev.x, ev.y) * t.scale;
    final to = box.localToGlobal(box.size.center(Offset.zero));
    setState(() => _flyers.add((_flyerId++, from, to)));
  }

  @override
  void dispose() {
    if (_engine.phase == RunPhase.failed) _recordFailureOnce();
    _coinBump.dispose();
    _ticker.dispose();
    _engine.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------- navigation
  Future<void> _leave(Widget Function() next) async {
    _recordFailureOnce();
    await _s.monetization.naturalBreak();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(fadeRoute(next()));
  }

  void _retry() => _leave(() => GameplayScreen(request: widget.request));

  /// Restart the whole level (drops any checkpoint).
  void _restartLevel() => _leave(() => GameplayScreen(request: RunRequest.level(_level.config.levelId)));

  /// Resume from the last checkpoint. The failed attempt is not recorded so
  /// stats before the checkpoint are not counted twice.
  void _retryFromCheckpoint() {
    final cp = _engine.checkpoint;
    if (cp == null) return _retry();
    _recorded = true;
    _leave(() => GameplayScreen(request: RunRequest.level(_level.config.levelId, resume: cp)));
  }

  void _next() {
    final l = _level.config.levelId;
    if (_kind != RunKind.level || l >= AppConfig.totalLevels) {
      _home();
      return;
    }
    _leave(() => GameplayScreen(request: RunRequest.level(l + 1)));
  }

  Future<void> _home() async {
    _recordFailureOnce();
    await _s.monetization.naturalBreak();
    if (!mounted) return;
    _s.audio.playMusic(MusicTrack.home);
    Navigator.of(context).pushAndRemoveUntil(fadeRoute(const HomeScreen()), (_) => false);
  }

  Future<void> _continueWithAd() async {
    final ok = await _s.monetization.rewarded(() {
      _continueUsed = true;
      _engine.revive();
    });
    if (!mounted) return;
    if (ok) {
      setState(() => _showFailure = false);
    } else {
      showToast(context, 'Ad not available right now', icon: Icons.wifi_off_rounded);
    }
  }

  Future<void> _doubleCoins() async {
    final r = _reward;
    if (r == null) return;
    final ok = await _s.monetization.rewarded(() => _s.progress.doubleReward(r));
    if (!mounted) return;
    if (ok) {
      _s.audio.play(Sfx.coin);
      setState(() {});
    } else {
      showToast(context, 'Ad not available right now', icon: Icons.wifi_off_rounded);
    }
  }

  void _setPaused(bool p) {
    if (_engine.phase != RunPhase.playing && _engine.phase != RunPhase.paused) return;
    setState(() => _paused = p);
    p ? _engine.pause() : _engine.resume();
  }

  // ------------------------------------------------------------------ input
  void _onPanStart(DragStartDetails d) {
    _panTotal = Offset.zero;
    _panStart = DateTime.now();
  }

  void _onPanUpdate(DragUpdateDetails d, double scale) {
    if (_introVisible || _paused) return;
    final delta = d.delta / scale;
    _panTotal += delta;
    _engine.onDrag(delta);
  }

  void _onPanEnd(DragEndDetails d, double scale) {
    if (_introVisible || _paused) return;
    final ms = DateTime.now().difference(_panStart).inMilliseconds;
    final speed = d.velocity.pixelsPerSecond.distance / scale / 1000; // units/ms
    // A flick (short + quick) shifts gravity; slower drags only steer.
    final quick = ms <= Physics.swipeMaxMillis && speed >= Physics.swipeMinSpeed * 0.6;
    final fast = ms <= 600 && speed >= Physics.swipeMinSpeed;
    if (_panTotal.distance >= Physics.swipeMinDistance && (quick || fast)) {
      _engine.onSwipe(GravityDir.fromVector(_panTotal));
    }
  }

  String get _title => switch (_kind) {
        RunKind.level => 'LEVEL ${_level.config.levelId}',
        RunKind.daily => 'DAILY · ${_level.config.modifier.title.toUpperCase()}',
        RunKind.endless => 'ENDLESS',
      };

  @override
  Widget build(BuildContext context) {
    final cfg = _level.config;
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_showResult || _showFailure) {
          _home();
        } else {
          _setPaused(!_paused);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bgDeep,
        body: LayoutBuilder(builder: (context, box) {
          final scale = math.min(box.maxWidth / Arena.width, box.maxHeight / Arena.height);
          _size = box.biggest;
          return Stack(fit: StackFit.expand, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _onPanStart,
              onPanUpdate: (d) => _onPanUpdate(d, scale),
              onPanEnd: (d) => _onPanEnd(d, scale),
              child: RepaintBoundary(child: CustomPaint(painter: _painter, size: Size.infinite)),
            ),
            HitVignette(hud: _engine.hud),
            GameHud(engine: _engine, title: _title, onPause: () => _setPaused(true), coinKey: _coinKey, coinBump: _coinBump),
            for (final (id, from, to) in _flyers)
              FlyingCoin(
                key: ValueKey(id),
                from: from,
                to: to,
                onDone: () {
                  setState(() => _flyers.removeWhere((f) => f.$1 == id));
                  _coinBump.value++;
                },
              ),
            Positioned(
              left: 0,
              right: 0,
              top: MediaQuery.of(context).padding.top + 150,
              child: IgnorePointer(child: Center(child: HintBanner(hud: _engine.hud))),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: box.maxHeight * 0.36,
              child: TutorialPromptView(hud: _engine.hud),
            ),
            if (_s.settings.gravityPad && !_showResult && !_showFailure)
              Positioned(
                right: 12,
                bottom: MediaQuery.of(context).padding.bottom + 12,
                child: GravityPad(onDir: _engine.onSwipe),
              ),
            if (_introVisible) _IntroCard(title: _title, config: cfg, resumed: _engine.resumed),
            if (_paused) _PauseOverlay(onResume: () => _setPaused(false), onRestart: _retry, onHome: _home),
            if (_showFailure)
              FailureScreen(
                stats: _engine.stats,
                progress: _engine.progress,
                endless: _kind == RunKind.endless,
                bestScore: _kind == RunKind.endless ? _prevEndlessBest : null,
                onRetry: _engine.checkpoint != null && _kind == RunKind.level ? _restartLevel : _retry,
                onRetryCheckpoint: _engine.checkpoint != null && _kind == RunKind.level ? _retryFromCheckpoint : null,
                onHome: _home,
                onContinue: !_continueUsed && !cfg.tutorial && _kind != RunKind.daily ? _continueWithAd : null,
              ),
            if (_showResult && _reward != null)
              ResultScreen(
                title: _title,
                stats: _engine.stats,
                reward: _reward!,
                config: cfg,
                onNext: _kind == RunKind.level ? _next : null,
                onRetry: _retry,
                onHome: _home,
                onDoubleCoins: _doubleCoins,
              ),
          ]);
        }),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.title, required this.config, this.resumed = false});
  final bool resumed;
  final String title;
  final LevelConfig config;
  @override
  Widget build(BuildContext context) {
    final world = WorldTheme.byId(config.worldId);
    final missions = config.objectives.where((o) => o.type != ObjectiveType.reachFinish).toList();
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 400),
        builder: (_, v, child) => Opacity(opacity: v, child: Transform.scale(scale: 0.9 + 0.1 * v, child: child)),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.bgDeep.withOpacity(0.86),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: world.accent.withOpacity(0.5)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(config.kind == RunKind.level ? world.name.toUpperCase() : 'COLOR GRAVITY',
                  style: AppText.label.copyWith(color: world.accent, letterSpacing: 2)),
              const SizedBox(height: 6),
              Text(title, textAlign: TextAlign.center, style: AppText.title.copyWith(fontSize: 28)),
              if (resumed) ...[
                const SizedBox(height: 8),
                const TierBadge(label: 'From checkpoint', color: Color(0xFF5CF2C2), small: true),
              ],
              if (config.kind == RunKind.level && !config.tutorial) ...[
                const SizedBox(height: 8),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  TierBadge(label: config.tier.label, color: Color(config.tier.argb), small: true),
                  if (config.isChallengeLevel) ...[
                    const SizedBox(width: 6),
                    const TierBadge(label: 'Challenge', color: AppColors.star, small: true),
                  ],
                ]),
              ],
              if (config.kind == RunKind.daily) ...[
                const SizedBox(height: 6),
                Text(config.modifier.description, style: AppText.bodyDim),
              ],
              for (final m in missions) ...[
                const SizedBox(height: 10),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.flag_rounded, size: 18, color: AppColors.star),
                  const SizedBox(width: 6),
                  Flexible(child: Text('Mission: ${m.describe()}', style: AppText.body)),
                ]),
              ],
              if (config.gravityMode != GravityMode.manual) ...[
                const SizedBox(height: 10),
                Text(config.gravityMode == GravityMode.rotating ? 'Gravity rotates on its own!' : 'Gravity flips on its own!',
                    style: AppText.body.copyWith(color: AppColors.brand2)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({required this.onResume, required this.onRestart, required this.onHome});
  final VoidCallback onResume, onRestart, onHome;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Material(
      color: AppColors.bgDeep.withOpacity(0.82),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('PAUSED', style: AppText.display.copyWith(fontSize: 34)),
                const SizedBox(height: 24),
                PrimaryButton(label: 'Resume', icon: Icons.play_arrow_rounded, onTap: onResume),
                const SizedBox(height: 10),
                SecondaryButton(label: 'Restart', icon: Icons.replay_rounded, onTap: onRestart),
                const SizedBox(height: 10),
                SecondaryButton(label: 'Home', icon: Icons.home_rounded, onTap: onHome),
                const SizedBox(height: 20),
                ListenableBuilder(
                  listenable: s.settings,
                  builder: (_, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _Toggle(
                        icon: s.settings.music ? Icons.music_note_rounded : Icons.music_off_rounded,
                        on: s.settings.music,
                        label: 'Music',
                        onTap: () => s.settings.music = !s.settings.music),
                    _Toggle(
                        icon: s.settings.sfx ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                        on: s.settings.sfx,
                        label: 'Sound',
                        onTap: () => s.settings.sfx = !s.settings.sfx),
                    _Toggle(
                        icon: Icons.vibration_rounded,
                        on: s.settings.vibration,
                        label: 'Vibration',
                        onTap: () => s.settings.vibration = !s.settings.vibration),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.icon, required this.on, required this.label, required this.onTap});
  final IconData icon;
  final bool on;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(children: [
          Pressable(
            onTap: onTap,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? AppColors.brand.withOpacity(0.25) : AppColors.surface,
                border: Border.all(color: on ? AppColors.brand : AppColors.stroke),
              ),
              child: Icon(icon, color: on ? AppColors.text : AppColors.textMute),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: AppText.label.copyWith(fontSize: 11)),
        ]),
      );
}
