import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/constants/game_constants.dart';
import '../../core/models/game_color.dart';
import '../../core/models/gravity_dir.dart';
import '../../levels/generators/level_generator.dart';
import '../../levels/models/level_config.dart';
import '../../levels/segments/segment_builder.dart';
import '../../progression/cosmetics.dart';
import '../collision/collision.dart';
import '../effects/particles.dart';
import '../entities/entity.dart';
import '../systems/color_system.dart';
import '../systems/gravity_system.dart';
import '../systems/objective_system.dart';
import '../systems/scoring.dart';

enum GameEventType {
  gravityShift,
  gravityWarning,
  gravityLocked,
  colorChange,
  collect,
  mismatch,
  coin,
  merge,
  hit,
  shieldBlock,
  perfect,
  powerUp,
  gatePass,
  combo,
  complete,
  fail,
  bomb,
  delivery,
  tutorialDone,
  checkpoint,
}

class GameEvent {
  const GameEvent(this.type, {this.text, this.value = 0, this.x = 0, this.y = 0});
  final GameEventType type;
  final String? text;
  final int value;

  /// Arena position of the event (used for coins flying to the HUD).
  final double x, y;
}

/// Where a Hard / Very Hard run resumes after "Retry from Checkpoint".
class CheckpointState {
  const CheckpointState({required this.track, required this.color, required this.gravity, required this.stats});
  final double track;
  final GameColor color;
  final GravityDir gravity;
  final RunStats stats;
}

enum RunPhase { playing, paused, completed, failed }

class TutorialPrompt {
  const TutorialPrompt(this.text, this.action, this.dir);
  final String text;
  final int action;
  final GravityDir? dir;
}

class Player {
  Player(this.color, this.hearts);
  double x = Arena.width / 2;
  double y = Arena.field.bottom - Arena.playerRadius;
  double vx = 0, vy = 0;
  GameColor color;
  int hearts;
  double angle = 0;
  double invuln = 0;
  bool shield = false;
  double colorPulse = 0;
  double squash = 0;
  final List<Offset> trail = [];
  double get r => Arena.playerRadius;
}

/// HUD values exposed as notifiers so widgets rebuild only on change.
class HudState {
  final score = ValueNotifier<int>(0);
  final coins = ValueNotifier<int>(0);
  final combo = ValueNotifier<int>(0);
  final hearts = ValueNotifier<int>(3);
  final shield = ValueNotifier<bool>(false);
  final gravity = ValueNotifier<GravityDir>(GravityDir.down);
  final warning = ValueNotifier<GravityDir?>(null);
  final locked = ValueNotifier<bool>(false);
  final color = ValueNotifier<GameColor>(GameColor.red);
  final progress = ValueNotifier<double>(0);
  final banner = ValueNotifier<String?>(null);
  final prompt = ValueNotifier<TutorialPrompt?>(null);
  final powerUps = ValueNotifier<List<(PowerUpType, double)>>(const []);
  final mission = ValueNotifier<String?>(null);

  /// Increments on every lost heart (drives the heart shake + red vignette).
  final hitPulse = ValueNotifier<int>(0);

  /// Remaining combo window 0..1 (0 when no combo is running).
  final comboTime = ValueNotifier<double>(0);
  String _powerSig = '';

  void setPowerUps(Map<PowerUpType, double> active) {
    final list = [
      for (final e in active.entries) (e.key, (e.value / e.key.duration).clamp(0.0, 1.0)),
    ];
    final sig = list.map((p) => '${p.$1.index}:${(p.$2 * 40).round()}').join(',');
    if (sig != _powerSig) {
      _powerSig = sig;
      powerUps.value = list;
    }
  }

  void dispose() {
    for (final n in [
      score,
      coins,
      combo,
      hearts,
      shield,
      gravity,
      warning,
      locked,
      color,
      progress,
      banner,
      prompt,
      powerUps,
      mission,
      hitPulse,
      comboTime,
    ]) {
      n.dispose();
    }
  }
}

/// Runs one Color Gravity session: level, daily challenge or endless.
/// Pure simulation — rendering, audio and haptics react to [drainEvents].
class GameEngine extends ChangeNotifier {
  GameEngine({required this.level, this.loadout = const Loadout(), CheckpointState? resume})
      : speed = level.config.speed,
        stats = resume?.stats.copy() ?? RunStats(),
        player = Player(resume?.color ?? level.config.startingColor, level.config.hearts) {
    gravity = GravitySystem(
      initial: resume?.gravity ?? config.startingGravity,
      smooth: config.smoothGravity,
      mode: config.gravityMode,
      interval: config.gravityInterval,
    );
    if (resume == null) stats.colorHistory.add(player.color);
    final finish = level.plan.entities.where((e) => e.kind == EntityKind.finish);
    _finishTrack = finish.isEmpty ? double.infinity : finish.first.trackY;
    _endlessRng = math.Random(config.seed);
    if (resume != null) _resumeFrom(resume);
    _syncHud();
  }

  /// Run-up distance shown before the checkpoint line when resuming.
  static const double resumeRunUp = 260;

  void _resumeFrom(CheckpointState cp) {
    checkpoint = cp;
    resumed = true;
    // The checkpoint line starts [resumeRunUp] above the resting player.
    traveled = cp.track - (Arena.height - player.y) - resumeRunUp;
    final plan = level.plan.entities;
    while (_spawnIndex < plan.length && plan[_spawnIndex].trackY <= cp.track) {
      _spawnIndex++;
    }
    player.invuln = 1.5;
  }

  final LoadedLevel level;
  final Loadout loadout;
  LevelConfig get config => level.config;
  bool get isEndless => config.kind == RunKind.endless;

  final ColorSystem colors = const ColorSystem();
  late final GravitySystem gravity;
  final ComboSystem combo = ComboSystem();
  final RunStats stats;
  final ParticlePool particles = ParticlePool();
  final List<FloatingText> texts = [];
  final GameCamera camera = GameCamera();
  final HudState hud = HudState();
  final List<Entity> entities = [];
  final Player player;
  final List<GameEvent> _events = [];
  final Map<PowerUpType, double> powerUps = {};
  final List<Entity> _hints = [];

  RunPhase phase = RunPhase.playing;
  double traveled = 0;
  double speed;
  double timeScale = 1;
  int stars = 0;
  bool continued = false;
  bool usedPowerUp = false;

  /// Last checkpoint reached in this run (null if none).
  CheckpointState? checkpoint;

  /// This run started from a checkpoint.
  bool resumed = false;

  double _hitStop = 0;
  int _spawnIndex = 0;
  double _finishTrack = double.infinity;
  Offset _steer = Offset.zero;
  double _dragAccum = 0;
  double _lastShiftAt = -99;
  double _lastColorChangeAt = -99;
  double _mergeChainTimer = 0;
  int _chain = 0;
  double _bannerTimer = 0;
  late math.Random _endlessRng;
  SegmentType? _endlessLast;

  // ------------------------------------------------------------------ input
  /// Drag delta in arena units (steers perpendicular to gravity).
  void onDrag(Offset delta) {
    if (phase != RunPhase.playing) return;
    _steer += delta * Physics.steerSensitivity;
    _steer = Offset(_steer.dx.clamp(-90.0, 90.0), _steer.dy.clamp(-90.0, 90.0));
    final p = hud.prompt.value;
    if (p != null && p.action == HintAction.drag) {
      _dragAccum += delta.distance;
      if (_dragAccum > 45) _completePrompt();
    }
  }

  /// Swipe: request a gravity shift.
  void onSwipe(GravityDir dir) {
    if (phase != RunPhase.playing) return;
    final control = powerUps.containsKey(PowerUpType.gravityControl);
    if (!config.swipeEnabled && !control) return;
    if (!gravity.canPlayerShift(override: control)) {
      _emit(GameEventType.gravityLocked);
      gravity.pulse = 0.4;
      return;
    }
    final change = gravity.request(dir, GravitySource.player, override: control);
    if (change != null) _onGravityChanged(change);
    final p = hud.prompt.value;
    if (p != null && p.action == HintAction.swipe && p.dir == dir) _completePrompt();
  }

  void _completePrompt() {
    hud.prompt.value = null;
    _dragAccum = 0;
    _text('NICE!', player.x, player.y - 40, const Color(0xFFFFFFFF), big: true);
    _emit(GameEventType.tutorialDone);
  }

  void pause() {
    if (phase == RunPhase.playing) phase = RunPhase.paused;
  }

  void resume() {
    if (phase == RunPhase.paused) phase = RunPhase.playing;
  }

  /// Rewarded continue: one more heart, brief invulnerability, cleared path.
  void revive() {
    if (phase != RunPhase.failed) return;
    continued = true;
    player.hearts = 1;
    player.invuln = 2.5;
    stats.failReason = null;
    for (final e in entities) {
      if (e.isHazard && (e.y - player.y).abs() < 260) e.alive = false;
    }
    entities.removeWhere((e) => !e.alive);
    phase = RunPhase.playing;
    _syncHud();
  }

  List<GameEvent> drainEvents() {
    if (_events.isEmpty) return const [];
    final out = List<GameEvent>.of(_events);
    _events.clear();
    return out;
  }

  // ----------------------------------------------------------------- update
  void update(double dt) {
    if (phase != RunPhase.playing) {
      notifyListeners();
      return;
    }
    dt = math.min(dt, 1 / 30);
    final targetScale = hud.prompt.value != null
        ? 0.12
        : powerUps.containsKey(PowerUpType.slowMotion)
            ? 0.6
            : 1.0;
    timeScale += (targetScale - timeScale) * math.min(1, dt * 8);
    var sdt = dt * timeScale;
    if (_hitStop > 0) {
      _hitStop -= dt;
      sdt *= 0.08;
    }
    stats.time += sdt;

    final scripted = gravity.update(sdt);
    if (scripted != null) _onGravityChanged(scripted);
    if (gravity.warning != null && hud.warning.value == null) _emit(GameEventType.gravityWarning);

    if (isEndless) {
      speed = config.speed + math.min(150, traveled * 0.0035);
      _extendEndless();
    }
    final scroll = speed * sdt;
    traveled += scroll;
    stats.distance = traveled;

    _spawn();
    _updateHints(scroll);
    _updatePlayer(sdt, dt);
    _updateEntities(sdt, scroll);
    _mergeOrbs();
    _interact();
    _updatePowerUps(sdt);

    combo.update(sdt);
    _mergeChainTimer -= sdt;
    if (_bannerTimer > 0) {
      _bannerTimer -= dt;
      if (_bannerTimer <= 0) hud.banner.value = null;
    }
    particles.update(sdt, scroll);
    for (final t in texts) {
      t.life -= dt;
      t.y -= 36 * dt;
    }
    texts.removeWhere((t) => t.life <= 0);
    camera.update(dt);

    if (!isEndless && _finishTrack.isFinite) {
      final finishY = Arena.height - (_finishTrack - traveled);
      if (finishY >= player.y) _complete();
    }
    _syncHud();
    notifyListeners();
  }

  void _extendEndless() {
    final b = level.builder;
    if (b.ctx.cursor - traveled > 2600) return;
    final vl = (25 + traveled / 350).floor().clamp(25, 400);
    b.ctx.adopt(LevelGenerator.configFor(vl, kind: RunKind.endless, seedOverride: _endlessRng.nextInt(1 << 30)));
    final specs = LevelGenerator.endlessBatch(vl, _endlessRng, _endlessLast);
    _endlessLast = specs.last.type;
    b.buildMore(specs);
  }

  void _spawn() {
    final plan = level.plan.entities;
    while (_spawnIndex < plan.length) {
      final t = plan[_spawnIndex];
      final y = Arena.height - (t.trackY - traveled);
      final ext = t.kind == EntityKind.hint ? 0.0 : t.halfExtent;
      if (y < -ext - 30) break;
      _spawnIndex++;
      final e = t.spawnCopy(y);
      if (e.kind == EntityKind.hint) {
        _hints.add(e);
      } else {
        entities.add(e);
      }
    }
  }

  void _updateHints(double scroll) {
    for (final h in _hints) {
      h.y += scroll;
      if (h.y >= 70 && h.alive) {
        h.alive = false;
        if (h.value != HintAction.none) {
          // Swipe prompt already satisfied?
          if (h.value == HintAction.swipe && h.dir == gravity.dir) continue;
          hud.prompt.value = TutorialPrompt(h.text ?? '', h.value, h.dir);
          _dragAccum = 0;
        } else {
          hud.banner.value = h.text;
          _bannerTimer = 2.6;
        }
      }
    }
    _hints.removeWhere((h) => !h.alive);
  }

  void _updatePlayer(double sdt, double realDt) {
    final p = player;
    final g = gravity.vector;
    p.vx += g.dx * Physics.playerGravity * sdt;
    p.vy += g.dy * Physics.playerGravity * sdt;
    final damp = math.exp(-10 * sdt);
    if (gravity.dir.isVertical) {
      p.vx *= damp;
    } else {
      p.vy *= damp;
    }
    p.vx = p.vx.clamp(-Physics.playerMaxFall, Physics.playerMaxFall);
    p.vy = p.vy.clamp(-Physics.playerMaxFall, Physics.playerMaxFall);

    // Steering along the axis perpendicular to gravity (1:1, capped speed).
    final maxStep = 950 * realDt;
    if (gravity.dir.isVertical) {
      final step = _steer.dx.clamp(-maxStep, maxStep);
      p.x += step;
      _steer = Offset(_steer.dx - step, 0);
    } else {
      final step = _steer.dy.clamp(-maxStep, maxStep);
      p.y += step;
      _steer = Offset(0, _steer.dy - step);
    }

    p.x += p.vx * sdt;
    p.y += p.vy * sdt;

    const f = Arena.field;
    final r = p.r;
    void land(double impact) {
      if (impact > 380) {
        p.squash = math.min(1, impact / 900);
        particles.emit(x: p.x, y: p.y, color: p.color.color, count: 5, speed: 90, life: 0.3, size: 2);
      }
    }

    if (p.x < f.left + r) {
      if (p.vx < 0) land(-p.vx);
      p.x = f.left + r;
      p.vx = g.dx < -0.5 ? -p.vx * 0.15 : 0;
    } else if (p.x > f.right - r) {
      if (p.vx > 0) land(p.vx);
      p.x = f.right - r;
      p.vx = g.dx > 0.5 ? -p.vx * 0.15 : 0;
    }
    if (p.y < f.top + r) {
      if (p.vy < 0) land(-p.vy);
      p.y = f.top + r;
      p.vy = g.dy < -0.5 ? -p.vy * 0.15 : 0;
    } else if (p.y > f.bottom - r) {
      if (p.vy > 0) land(p.vy);
      p.y = f.bottom - r;
      p.vy = g.dy > 0.5 ? -p.vy * 0.15 : 0;
    }

    // Reorient toward gravity (shortest arc).
    final target = gravity.dir.angle;
    var diff = (target - p.angle) % (math.pi * 2);
    if (diff > math.pi) diff -= math.pi * 2;
    if (diff < -math.pi) diff += math.pi * 2;
    p.angle += diff * math.min(1, realDt * 12);

    p.invuln = math.max(0, p.invuln - sdt);
    p.colorPulse = math.max(0, p.colorPulse - realDt * 2.5);
    p.squash = math.max(0, p.squash - realDt * 5);
    p.trail.insert(0, Offset(p.x, p.y));
    if (p.trail.length > 14) p.trail.removeLast();
    for (var i = 0; i < p.trail.length; i++) {
      p.trail[i] = p.trail[i].translate(0, speed * sdt * 0.9);
    }
  }

  void _updateEntities(double sdt, double scroll) {
    final g = gravity.vector;
    final magnet = powerUps.containsKey(PowerUpType.magnet);
    for (final e in entities) {
      e.age += sdt;
      e.y += scroll;
      e.flash = math.max(0, e.flash - sdt);
      switch (e.kind) {
        case EntityKind.block:
          if (e.motion == BlockMotion.sway) {
            e.x = e.baseX + math.sin((e.age + e.phase) / e.period * math.pi * 2) * e.amp;
          } else if (e.motion == BlockMotion.crusher) {
            // Gravity crusher: slides along with gravity.
            e.x = (e.x + g.dx * 300 * sdt).clamp(Arena.wallLeft + e.w / 2, Arena.wallRight - e.w / 2);
            e.y += g.dy * 70 * sdt;
          }
        case EntityKind.rotor:
          e.angle += e.angSpeed * sdt;
        case EntityKind.orb:
        case EntityKind.meteor:
          _updateLoose(e, sdt, g, magnet);
        case EntityKind.coin:
          if (magnet) _attract(e, sdt, 150, 520);
        default:
          break;
      }
      final ext = e.halfExtent;
      if (e.y - ext > Arena.height + 40 || (e.isLoose && e.y < -360)) e.alive = false;
    }
    entities.removeWhere((e) => !e.alive);
  }

  void _attract(Entity e, double sdt, double radius, double strength) {
    final dx = player.x - e.x, dy = player.y - e.y;
    final d2 = dx * dx + dy * dy;
    if (d2 > radius * radius || d2 < 1) return;
    final d = math.sqrt(d2);
    e.x += dx / d * strength * sdt;
    e.y += dy / d * strength * sdt;
  }

  void _updateLoose(Entity e, double sdt, Offset g, bool magnet) {
    if (e.behavior != OrbBehavior.anchor) {
      final dirMul = e.behavior == OrbBehavior.reverse ? -1.0 : 1.0;
      final accel = e.kind == EntityKind.meteor ? Physics.looseGravity * 1.3 : Physics.looseGravity;
      e.vx += g.dx * accel * dirMul * sdt;
      e.vy += g.dy * accel * dirMul * sdt;
      final damp = math.exp(-1.2 * sdt);
      e.vx *= damp;
      e.vy *= damp;
      e.vx = e.vx.clamp(-Physics.looseMaxSpeed, Physics.looseMaxSpeed);
      e.vy = e.vy.clamp(-Physics.looseMaxSpeed, Physics.looseMaxSpeed);
      e.x += e.vx * sdt;
      e.y += e.vy * sdt;
    }
    if (magnet && e.kind == EntityKind.orb && colors.canCollect(player.color, e)) _attract(e, sdt, 160, 380);
    if (e.x < Arena.wallLeft + e.r) {
      e.x = Arena.wallLeft + e.r;
      e.vx = e.vx.abs() * 0.2;
    } else if (e.x > Arena.wallRight - e.r) {
      e.x = Arena.wallRight - e.r;
      e.vx = -e.vx.abs() * 0.2;
    }
    if (e.kind != EntityKind.orb) return;
    for (final z in entities) {
      switch (z.kind) {
        case EntityKind.mergeZone:
          final rect = z.rect;
          if (rect.contains(Offset(e.x, e.y))) {
            e.x = e.x.clamp(rect.left + e.r, rect.right - e.r);
            e.y = e.y.clamp(rect.top + e.r, rect.bottom - e.r);
            if (e.x <= rect.left + e.r || e.x >= rect.right - e.r) e.vx = 0;
            if (e.y <= rect.top + e.r || e.y >= rect.bottom - e.r) e.vy = 0;
            e.triggered = true; // inside a merge zone
          }
        case EntityKind.gate:
          if (!colors.orbPassesGate(z, e) && Collision.circleRect(e.x, e.y, e.r, z.rect)) {
            // Color filter: wrong-colored orbs rest on the barrier.
            if (e.vy >= 0) {
              e.y = z.rect.top - e.r;
            } else {
              e.y = z.rect.bottom + e.r;
            }
            e.vy = 0;
          }
        case EntityKind.basin:
          if (z.rect.contains(Offset(e.x, e.y)) && colors.basinAccepts(z, e) && e.alive) {
            e.alive = false;
            z.flash = 0.4;
            stats.deliveries++;
            stats.colorMatches++;
            final pts = 30 * e.level * combo.multiplier;
            stats.score += pts;
            if (combo.hit()) _comboCallout();
            _text('COLOR MATCH +$pts', z.x, z.y - z.h / 2 - 10, z.color!.color);
            particles.emit(x: e.x, y: e.y, color: z.color!.color, count: 14, speed: 140, life: 0.5);
            _emit(GameEventType.delivery);
          }
        case EntityKind.gravitySwitch:
          if (!z.triggered &&
              z.triggerColor != null &&
              z.triggerColor == e.color &&
              Collision.circleCircle(e.x, e.y, e.r, z.x, z.y, z.r)) {
            _triggerSwitch(z);
          }
        default:
          break;
      }
    }
  }

  void _mergeOrbs() {
    final mega = powerUps.containsKey(PowerUpType.megaMerge);
    final orbs = entities.where((e) => e.kind == EntityKind.orb && e.alive).toList();
    for (var i = 0; i < orbs.length; i++) {
      final a = orbs[i];
      if (!a.alive) continue;
      for (var j = i + 1; j < orbs.length; j++) {
        final b = orbs[j];
        if (!b.alive) continue;
        final dx = b.x - a.x, dy = b.y - a.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        final reach = (a.r + b.r) * (mega ? 1.7 : 1.0);
        if (dist >= reach) continue;
        if (colors.canMerge(a, b, mega: mega)) {
          _merge(a, b);
          break;
        } else if (dist < a.r + b.r && dist > 0.01) {
          // Separate overlapping orbs.
          final push = (a.r + b.r - dist) / 2;
          final nx = dx / dist, ny = dy / dist;
          a.x -= nx * push;
          a.y -= ny * push;
          b.x += nx * push;
          b.y += ny * push;
        }
      }
    }
    entities.removeWhere((e) => !e.alive);
  }

  void _merge(Entity a, Entity b) {
    a.alive = false;
    b.alive = false;
    final lvl = math.min(6, math.max(a.level, b.level) + 1);
    final c = colors.mergedColor(a, b);
    final inZone = a.triggered || b.triggered;
    final n = Entity(
      kind: EntityKind.orb,
      x: (a.x + b.x) / 2,
      y: (a.y + b.y) / 2,
      r: Entity.orbRadius(lvl),
      color: c,
      level: lvl,
      wildcard: c == null,
    )
      ..vx = (a.vx + b.vx) / 2
      ..vy = (a.vy + b.vy) / 2
      ..flash = 0.45
      ..triggered = inZone;
    entities.add(n);

    _chain = _mergeChainTimer > 0 ? _chain + 1 : 1;
    _mergeChainTimer = 1.1;
    stats.merges++;
    stats.maxMergeLevel = math.max(stats.maxMergeLevel, lvl);
    if (_chain >= 2) stats.chainMerges++;
    final pts = 20 * lvl * _chain * (inZone ? 2 : 1);
    stats.score += pts;
    final color = (c ?? GameColor.yellow).color;
    _mergeFx(n.x, n.y, color, lvl);
    _hitStop = 0.05;
    if (lvl >= 3) camera.pulse(0.035);

    String label = 'COMBINE +$pts';
    if (_chain >= 3) {
      label = 'COLOR CHAIN! +$pts';
    } else if (_chain == 2) {
      label = 'x2 COMBO +$pts';
    }
    _text(label, n.x, n.y - 24, color, big: _chain >= 2 || lvl >= 3);
    if (_chain >= 2 || lvl >= 3 || inZone) {
      stats.perfectMerges++;
      _emit(GameEventType.perfect, text: 'PERFECT MERGE');
    }
    if (stats.time - _lastShiftAt < 1.2) _gravityCombo();
    if (combo.hit()) _comboCallout();
    _emit(GameEventType.merge, value: lvl);
  }

  void _mergeFx(double x, double y, Color color, int lvl) {
    final big = lvl >= 3 ? 1.5 : 1.0;
    switch (loadout.mergeFx) {
      case 'mfx_ring':
        particles.ring(x: x, y: y, color: color, size: 34 * big);
        particles.ring(x: x, y: y, color: const Color(0xFFFFFFFF), size: 22 * big, life: 0.3);
        particles.emit(x: x, y: y, color: color, count: 8, speed: 120, life: 0.4);
      case 'mfx_crystal':
        particles.emit(
            x: x, y: y, color: color, count: (14 * big).round(), speed: 200, life: 0.6, size: 5, style: ParticleStyle.shard);
      case 'mfx_energy':
        particles.emit(
            x: x, y: y, color: color, count: (16 * big).round(), speed: 240, life: 0.45, size: 3, style: ParticleStyle.spark);
        particles.ring(x: x, y: y, color: color, size: 28 * big);
      default:
        particles.emit(x: x, y: y, color: color, count: (16 * big).round(), speed: 180, life: 0.55, size: 3.4);
        particles.emit(x: x, y: y, color: const Color(0xFFFFFFFF), count: 6, speed: 90, life: 0.35, size: 2);
    }
  }

  void _interact() {
    final p = player;
    final r = p.r;
    final colorFrozen = powerUps.containsKey(PowerUpType.colorFreeze);
    var inLock = false;
    Entity? inZone;

    for (final e in entities) {
      if (!e.alive) continue;
      switch (e.kind) {
        case EntityKind.orb:
          if (Collision.circleCircle(p.x, p.y, r, e.x, e.y, e.r)) {
            if (colors.canCollect(p.color, e)) {
              _collectOrb(e);
            } else if (!e.passed) {
              e.passed = true;
              // Wrong color: the orb bounces off and the combo breaks.
              final dx = e.x - p.x, dy = e.y - p.y;
              final d = math.max(1.0, math.sqrt(dx * dx + dy * dy));
              e.vx = dx / d * 320;
              e.vy = dy / d * 320;
              if (combo.combo > 0) _text('COMBO LOST', p.x, p.y - 30, const Color(0xFFA3ABCC));
              combo.breakCombo();
              _emit(GameEventType.mismatch);
            }
          }
        case EntityKind.coin:
          if (Collision.circleCircle(p.x, p.y, r + 4, e.x, e.y, e.r)) {
            e.alive = false;
            final v = powerUps.containsKey(PowerUpType.doubleCoins) ? 2 : 1;
            stats.coins += v;
            stats.score += 5;
            particles.emit(x: e.x, y: e.y, color: const Color(0xFFFFC23D), count: 5, speed: 90, life: 0.35, size: 2);
            _emit(GameEventType.coin, x: e.x, y: e.y);
          }
        case EntityKind.block:
        case EntityKind.spikes:
        case EntityKind.laser:
        case EntityKind.rotor:
        case EntityKind.meteor:
          _hazard(e, colorFrozen);
        case EntityKind.gate:
          if (!e.passed && Collision.circleRect(p.x, p.y, r, e.rect)) {
            e.passed = true;
            final res = colors.gateCheck(e, p.color, gravity.dir, colorFrozen: colorFrozen);
            if (res == GateResult.pass) {
              _passGate(e);
            } else {
              e.triggered = true;
              e.flash = 0.5;
              _hit(res == GateResult.wrongColor ? 'Wrong color at a gate' : 'Wrong gravity at a gate');
            }
          }
        case EntityKind.colorSwitch:
          final touching =
              e.fullWidth ? Collision.circleRect(p.x, p.y, r, e.rect) : Collision.circleCircle(p.x, p.y, r, e.x, e.y, e.r);
          if (touching && e.color != p.color) {
            _setColor(e.color!);
            e.flash = 0.4;
          }
        case EntityKind.gravitySwitch:
          if (!e.triggered &&
              Collision.circleCircle(p.x, p.y, r, e.x, e.y, e.r) &&
              (e.triggerColor == null || e.triggerColor == p.color)) {
            _triggerSwitch(e);
          }
        case EntityKind.checkpoint:
          if (!e.passed && e.y >= p.y) {
            e.passed = true;
            e.flash = 0.6;
            checkpoint = CheckpointState(track: e.trackY, color: p.color, gravity: gravity.dir, stats: stats.copy());
            _text('CHECKPOINT', Arena.width / 2, p.y - 60, const Color(0xFF5CF2C2), big: true);
            particles.emit(x: p.x, y: p.y, color: const Color(0xFF5CF2C2), count: 18, speed: 200, life: 0.6);
            _emit(GameEventType.checkpoint);
          }
        case EntityKind.gravityZone:
          if (e.rect.contains(Offset(p.x, p.y))) inZone = e;
        case EntityKind.lockZone:
          if (e.rect.contains(Offset(p.x, p.y))) inLock = true;
        case EntityKind.powerUp:
          if (Collision.circleCircle(p.x, p.y, r + 4, e.x, e.y, e.r)) {
            e.alive = false;
            _activatePowerUp(e.powerUp!);
          }
        case EntityKind.special:
          if (Collision.circleCircle(p.x, p.y, r + 4, e.x, e.y, e.r)) {
            e.alive = false;
            _activateSpecial(e);
          }
        default:
          break;
      }
    }

    gravity.zoneLocked = inLock && !powerUps.containsKey(PowerUpType.gravityControl);
    if (inZone != null && gravity.activeZone != inZone) {
      final ch = gravity.enterZone(inZone);
      if (ch != null) _onGravityChanged(ch);
    } else if (inZone == null && gravity.activeZone != null) {
      final ch = gravity.exitZone();
      if (ch != null) _onGravityChanged(ch);
    }
  }

  void _hazard(Entity e, bool colorFrozen) {
    final p = player;
    final dangerous = colors.isDangerous(e, p.color, colorFrozen: colorFrozen);
    if (!dangerous) return;
    final dist = Collision.hazardDistance(e, p.x, p.y, gravity.dir) - p.r;
    if (dist < 0) {
      if (!e.triggered) {
        e.triggered = true;
        e.flash = 0.4;
        _hit(_reasonFor(e));
      }
    } else if (dist < 12) {
      e.nearMiss = true;
    }
    if (!e.passed && e.y - e.halfExtent > p.y + p.r) {
      e.passed = true;
      if (e.nearMiss && !e.triggered && e.kind != EntityKind.laser) {
        stats.perfectDodges++;
        stats.score += 25;
        _text('PERFECT DODGE', p.x, p.y - 34, const Color(0xFFFFFFFF));
        _emit(GameEventType.perfect, text: 'PERFECT DODGE');
        if (stats.time - _lastShiftAt < GameTiming.perfectShiftWindow) _perfectShift();
        if (combo.hit()) _comboCallout();
      }
    }
  }

  String _reasonFor(Entity e) => switch (e.kind) {
        EntityKind.spikes =>
          e.dangerColor != null ? '${e.dangerColor!.label} spikes hurt ${e.dangerColor!.label}' : 'Hit the spikes',
        EntityKind.laser => 'Caught by a laser',
        EntityKind.rotor => 'Clipped by a rotor',
        EntityKind.meteor => 'Struck by a meteor',
        EntityKind.block => e.motion == BlockMotion.crusher ? 'Crushed' : 'Hit a barrier',
        _ => 'Collision',
      };

  void _collectOrb(Entity e) {
    final p = player;
    e.alive = false;
    stats.orbsCollected++;
    stats.colorMatches++;
    final pts = 10 * e.level * combo.multiplier;
    stats.score += pts;
    final color = (e.color ?? p.color).color;
    particles.emit(x: e.x, y: e.y, color: color, count: 8 + e.level * 2, speed: 120, life: 0.45, size: 2.6);
    if (e.level >= 2 || e.wildcard) {
      stats.perfectMatches++;
      _text(e.wildcard ? 'WILDCARD +$pts' : 'PERFECT MATCH +$pts', e.x, e.y - 20, color, big: true);
      _emit(GameEventType.perfect, text: 'PERFECT MATCH');
    } else {
      _text('+$pts', e.x, e.y - 16, color);
    }
    if (combo.hit()) _comboCallout();
    _emit(GameEventType.collect, value: e.level);
  }

  void _passGate(Entity e) {
    stats.gatesPassed++;
    e.flash = 0.5;
    stats.score += 25;
    final hasRequirement = e.gateColors != null || e.gateDir != null;
    final justInTime = stats.time - math.max(_lastShiftAt, _lastColorChangeAt) < 1.4;
    if (hasRequirement && justInTime) {
      stats.perfectGates++;
      stats.score += 40;
      _text('PERFECT GATE', player.x, player.y - 36, const Color(0xFFFFFFFF), big: true);
      _emit(GameEventType.perfect, text: 'PERFECT GATE');
      if (stats.time - _lastShiftAt < GameTiming.perfectShiftWindow + 0.6 && e.gateDir != null) _perfectShift();
    }
    final color = e.gateColors?.first.color ?? const Color(0xFFFFFFFF);
    particles.emit(
        x: player.x, y: e.y, color: color, count: 12, speed: 160, life: 0.45, spread: math.pi, direction: -math.pi / 2);
    if (combo.hit()) _comboCallout();
    _emit(GameEventType.gatePass);
    if (e.effectDir != null) {
      final ch = gravity.request(e.effectDir!, GravitySource.gate);
      if (ch != null) _onGravityChanged(ch);
    }
  }

  void _triggerSwitch(Entity e) {
    e.triggered = true;
    e.flash = 0.5;
    final ch = gravity.request(e.dir!, GravitySource.switchPad);
    if (ch != null) _onGravityChanged(ch);
  }

  void _perfectShift() {
    stats.perfectShifts++;
    stats.score += 40;
    _lastShiftAt = -99; // one perfect per shift
    _text('PERFECT SHIFT', player.x, player.y - 52, const Color(0xFF9FD8FF), big: true);
    _emit(GameEventType.perfect, text: 'PERFECT SHIFT');
  }

  void _gravityCombo() {
    stats.perfectShifts++;
    stats.score += 60;
    _lastShiftAt = -99;
    _text('GRAVITY COMBO!', player.x, player.y - 60, const Color(0xFF9FD8FF), big: true);
    _emit(GameEventType.perfect, text: 'GRAVITY COMBO');
  }

  void _comboCallout() {
    stats.maxCombo = math.max(stats.maxCombo, combo.combo);
    _text('x${combo.combo} COMBO', Arena.width / 2, Arena.field.top + 10, const Color(0xFFFFD45C), big: true);
    _emit(GameEventType.combo, value: combo.combo);
  }

  void _onGravityChanged(GravityChange ch) {
    final playerShift = ch.source == GravitySource.player;
    if (playerShift) {
      stats.gravityShifts++;
      stats.shiftsByDir[ch.to] = (stats.shiftsByDir[ch.to] ?? 0) + 1;
      _lastShiftAt = stats.time;
      if (powerUps.containsKey(PowerUpType.perfectGravity)) _perfectShift();
    } else {
      _text('GRAVITY ${ch.to.arrow}', Arena.width / 2, Arena.field.top + 40, const Color(0xFFFFFFFF), big: true);
    }
    camera.pulse(0.018);
    _gravityFx(ch.to);
    _emit(GameEventType.gravityShift, value: playerShift ? 1 : 0);
  }

  void _gravityFx(GravityDir d) {
    final p = player;
    final dirAngle = math.atan2(d.dy.toDouble(), d.dx.toDouble());
    final c = p.color.color;
    switch (loadout.gravityFx) {
      case 'gfx_particle':
        particles.emit(
            x: p.x, y: p.y, color: const Color(0xFFFFFFFF), count: 18, speed: 260, life: 0.5, spread: 1.2, direction: dirAngle);
      case 'gfx_lightning':
        particles.emit(
            x: p.x,
            y: p.y,
            color: const Color(0xFFFFF27A),
            count: 12,
            speed: 320,
            life: 0.3,
            spread: 1.0,
            direction: dirAngle,
            style: ParticleStyle.spark,
            size: 3);
        particles.ring(x: p.x, y: p.y, color: const Color(0xFFFFF27A), size: 26);
      case 'gfx_spiral':
        for (var i = 0; i < 3; i++) {
          particles.emit(
              x: p.x,
              y: p.y,
              color: c,
              count: 6,
              speed: 150 + i * 40.0,
              life: 0.6,
              spread: math.pi * 2,
              direction: i * 2.0,
              size: 2.5);
        }
        particles.ring(x: p.x, y: p.y, color: c, size: 30);
      default:
        particles.ring(x: p.x, y: p.y, color: c, size: 32);
        particles.emit(
            x: p.x, y: p.y, color: c, count: 10, speed: 200, life: 0.4, spread: 0.9, direction: dirAngle + math.pi, size: 2.4);
    }
  }

  void _setColor(GameColor c) {
    player.color = c;
    player.colorPulse = 1;
    _lastColorChangeAt = stats.time;
    stats.colorHistory.add(c);
    particles.ring(x: player.x, y: player.y, color: c.color, size: 30);
    particles.emit(x: player.x, y: player.y, color: c.color, count: 12, speed: 140, life: 0.45);
    _text(c.label.toUpperCase(), player.x, player.y - 30, c.color);
    _emit(GameEventType.colorChange);
  }

  void _hit(String reason) {
    final p = player;
    if (p.invuln > 0) return;
    if (p.shield) {
      p.shield = false;
      p.invuln = 1.0;
      particles.ring(x: p.x, y: p.y, color: const Color(0xFF9FD8FF), size: 40);
      _text('SHIELD!', p.x, p.y - 30, const Color(0xFF9FD8FF), big: true);
      camera.shake(5);
      _emit(GameEventType.shieldBlock);
      return;
    }
    p.hearts--;
    stats.hits++;
    hud.hitPulse.value++;
    combo.breakCombo();
    p.invuln = GameTiming.invulnerable;
    camera.shake(10);
    particles.emit(x: p.x, y: p.y, color: const Color(0xFFFF5470), count: 18, speed: 220, life: 0.5, size: 3);
    _emit(GameEventType.hit);
    if (p.hearts <= 0) _fail(reason);
  }

  void _activatePowerUp(PowerUpType t) {
    stats.powerUpsUsed++;
    usedPowerUp = true;
    switch (t) {
      case PowerUpType.shield:
        player.shield = true;
      case PowerUpType.colorShift:
        _setColor(_nextGateColor() ?? _otherPaletteColor());
      default:
        powerUps[t] = t.duration;
    }
    if (t == PowerUpType.gravityFreeze) gravity.frozen = true;
    particles.ring(x: player.x, y: player.y, color: const Color(0xFFFFFFFF), size: 36);
    _text(t.title.toUpperCase(), player.x, player.y - 40, const Color(0xFFFFFFFF), big: true);
    _emit(GameEventType.powerUp, text: t.title);
  }

  GameColor? _nextGateColor() {
    final upcoming = [...entities.where((e) => e.kind == EntityKind.gate && !e.passed && e.y < player.y)]
      ..sort((a, b) => b.y.compareTo(a.y));
    for (final g in upcoming) {
      final cs = g.gateColors;
      if (cs == null) continue;
      if (g.gateMode == GateMode.allow) return cs.first;
      return config.palette.firstWhere((c) => !cs.contains(c), orElse: () => player.color);
    }
    final plan = level.plan.entities;
    for (var i = _spawnIndex; i < plan.length && i < _spawnIndex + 40; i++) {
      final g = plan[i];
      if (g.kind == EntityKind.gate && g.gateColors != null && g.gateMode == GateMode.allow) return g.gateColors!.first;
    }
    return null;
  }

  GameColor _otherPaletteColor() {
    final others = config.palette.where((c) => c != player.color).toList();
    return others.isEmpty ? player.color : others[math.Random().nextInt(others.length)];
  }

  void _activateSpecial(Entity e) {
    final p = player;
    switch (e.special!) {
      case SpecialKind.bomb:
        var n = 0;
        for (final h in entities) {
          if (h.isHazard && (h.y - p.y).abs() < 220) {
            h.alive = false;
            n++;
            particles.emit(x: h.x, y: h.y, color: const Color(0xFFFF9F5A), count: 10, speed: 200, life: 0.5);
          }
        }
        camera.shake(9);
        _text(n > 0 ? 'BOOM! ×$n' : 'BOOM!', p.x, p.y - 40, const Color(0xFFFF9F5A), big: true);
        _emit(GameEventType.bomb);
      case SpecialKind.gravityBomb:
        final ch = gravity.temporaryReverse(3);
        if (ch != null) _onGravityChanged(ch);
      case SpecialKind.gravityCore:
        final ch = gravity.request(gravity.dir.opposite, GravitySource.core);
        if (ch != null) _onGravityChanged(ch);
      case SpecialKind.colorCore:
        _setColor(e.color ?? _otherPaletteColor());
    }
  }

  void _updatePowerUps(double sdt) {
    if (powerUps.isEmpty) return;
    final expired = <PowerUpType>[];
    powerUps.updateAll((k, v) {
      final n = v - sdt;
      if (n <= 0) expired.add(k);
      return n;
    });
    for (final k in expired) {
      powerUps.remove(k);
      if (k == PowerUpType.gravityFreeze) gravity.frozen = false;
    }
  }

  void _complete() {
    final unmet = ObjectiveSystem.unmetRequired(config, stats, player.color);
    if (unmet.isNotEmpty) {
      _fail('Mission incomplete · ${unmet.first.describe()}');
      return;
    }
    if (stats.hits == 0) {
      stats.score += 500;
      stats.perfectMatches++;
      _text('PERFECT RUN', Arena.width / 2, Arena.height / 2, const Color(0xFFFFD45C), big: true);
    }
    stats.maxCombo = math.max(stats.maxCombo, combo.best);
    phase = RunPhase.completed;
    stars = ObjectiveSystem.stars(config, stats, player.color);
    for (var i = 0; i < 4; i++) {
      particles.emit(
          x: 60 + i * 80.0,
          y: player.y,
          color: config.palette[i % config.palette.length].color,
          count: 16,
          speed: 260,
          life: 0.9,
          direction: -math.pi / 2,
          spread: 1.4);
    }
    _syncHud();
    _emit(GameEventType.complete, value: stars);
  }

  void _fail(String reason) {
    stats.failReason = reason;
    stats.maxCombo = math.max(stats.maxCombo, combo.best);
    phase = RunPhase.failed;
    camera.shake(12);
    _syncHud();
    _emit(GameEventType.fail, text: reason);
  }

  // ------------------------------------------------------------------ utils
  void _emit(GameEventType t, {String? text, int value = 0, double x = 0, double y = 0}) =>
      _events.add(GameEvent(t, text: text, value: value, x: x, y: y));

  void _text(String s, double x, double y, Color c, {bool big = false}) {
    if (texts.length > 10) texts.removeAt(0);
    texts.add(FloatingText(s, x.clamp(70.0, Arena.width - 70), y, c, big: big));
  }

  double get progress {
    if (isEndless || !_finishTrack.isFinite) return 0;
    return ((traveled + Arena.height - player.y) / _finishTrack).clamp(0.0, 1.0);
  }

  void _syncHud() {
    hud.score.value = stats.score;
    hud.coins.value = stats.coins;
    hud.combo.value = combo.combo;
    hud.comboTime.value = combo.combo >= 2 ? ((combo.timer / GameTiming.comboWindow) * 20).ceil() / 20 : 0;
    hud.hearts.value = player.hearts;
    hud.shield.value = player.shield;
    hud.gravity.value = gravity.dir;
    hud.warning.value = gravity.warning;
    hud.locked.value = !config.swipeEnabled && !powerUps.containsKey(PowerUpType.gravityControl)
        ? config.levelId != 1
        : !gravity.canPlayerShift(override: powerUps.containsKey(PowerUpType.gravityControl));
    hud.color.value = player.color;
    hud.progress.value = (progress * 200).round() / 200;
    hud.setPowerUps(powerUps);
    final missions = config.objectives.where((o) => o.type != ObjectiveType.reachFinish);
    if (missions.isNotEmpty) {
      final o = missions.first;
      final (cur, target) = ObjectiveSystem.progress(o, stats, finalColor: player.color);
      hud.mission.value = '${o.describe()} · ${math.min(cur, target)}/$target';
    }
  }

  @override
  void dispose() {
    hud.dispose();
    super.dispose();
  }
}
