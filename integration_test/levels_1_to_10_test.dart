import 'dart:math' as math;
import 'dart:ui';

import 'package:color_gravity/core/models/gravity_dir.dart';
import 'package:color_gravity/core/theme/app_theme.dart';
import 'package:color_gravity/game/engine/game_engine.dart';
import 'package:color_gravity/game/entities/entity.dart';
import 'package:color_gravity/screens/gameplay/gameplay_screen.dart';
import 'package:color_gravity/services/app_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Plays levels 1-10 on a real device/emulator through the real UI:
/// gameplay screen → result screen → "Next Level". A simple autopilot steers
/// toward coins/matching orbs and performs gravity shifts; it is given
/// invulnerability so the test checks flow, progression and stability (not skill).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('levels 1-10 play to completion on device', (tester) async {
    final services = AppServices.offline();
    final frameTimes = <double>[];
    void onTimings(List<FrameTiming> t) {
      for (final f in t) {
        frameTimes.add(f.totalSpan.inMicroseconds / 1000);
      }
    }

    SchedulerBinding.instance.addTimingsCallback(onTimings);

    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(theme: AppTheme.build(), home: const GameplayScreen(request: RunRequest.level(1))),
    ));

    final report = <String>[];
    for (var level = 1; level <= 10; level++) {
      // Wait for the run to start.
      await tester.pump(const Duration(milliseconds: 200));
      final engine = GameplayScreen.debugEngine!;
      expect(engine.config.levelId, level);
      var t = 0.0;
      var lastShift = 0.0;
      var shiftStep = 0;
      final rng = math.Random(level);
      while (engine.phase != RunPhase.completed && t < 120) {
        if (engine.phase == RunPhase.failed) {
          fail('level $level failed: ${engine.stats.failReason}');
        }
        engine.player.invuln = 2;
        _autopilot(engine, t, rng);
        // Tutorial prompts and periodic gravity shifts.
        final p = engine.hud.prompt.value;
        if (p != null) {
          p.dir != null ? engine.onSwipe(p.dir!) : engine.onDrag(const Offset(50, 0));
        } else if (t - lastShift > 2.5 && engine.config.swipeEnabled) {
          lastShift = t;
          final up = shiftStep.isEven;
          shiftStep++;
          engine.onSwipe(up ? GravityDir.up : GravityDir.down);
        }
        await tester.pump(const Duration(milliseconds: 33));
        t += 0.033;
      }
      expect(engine.phase, RunPhase.completed, reason: 'level $level timed out');
      await tester.pump(const Duration(milliseconds: 1400));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('LEVEL COMPLETE'), findsOneWidget, reason: 'result screen for level $level');
      expect(services.progress.unlockedLevel, level + 1);
      report.add('L$level stars=${engine.stars} score=${engine.stats.score} coins=${engine.stats.coins} '
          'matches=${engine.stats.colorMatches} merges=${engine.stats.merges} shifts=${engine.stats.gravityShifts} '
          'hits=${engine.stats.hits} time=${t.toStringAsFixed(1)}s');
      if (level < 10) {
        await tester.tap(find.text('Next Level'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      // Sanity: no hidden exceptions.
      expect(tester.takeException(), isNull);
    }

    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    frameTimes.sort();
    final avg = frameTimes.isEmpty ? 0 : frameTimes.reduce((a, b) => a + b) / frameTimes.length;
    final p90 = frameTimes.isEmpty ? 0 : frameTimes[(frameTimes.length * 0.9).floor()];
    binding.reportData = {
      'levels': report,
      'frames': frameTimes.length,
      'avgFrameMs': avg.toStringAsFixed(2),
      'p90FrameMs': p90.toStringAsFixed(2),
      'stars': services.progress.data.totalStars,
      'coins': services.progress.coins,
    };
    // ignore: avoid_print
    print('REPORT ${binding.reportData}');
  });
}

/// Steer toward the nearest coin or collectible orb ahead of the player.
void _autopilot(GameEngine e, double t, math.Random rng) {
  final p = e.player;
  Entity? best;
  var bestD = double.infinity;
  for (final x in e.entities) {
    final good = x.kind == EntityKind.coin || (x.kind == EntityKind.orb && e.colors.canCollect(p.color, x));
    if (!good || x.y > p.y + 10 || x.y < p.y - 320) continue;
    final d = (x.x - p.x).abs() + (p.y - x.y) * 0.3;
    if (d < bestD) {
      bestD = d;
      best = x;
    }
  }
  if (best == null) return;
  if (e.gravity.dir.isVertical) {
    e.onDrag(Offset((best.x - p.x).clamp(-6.0, 6.0), 0));
  } else {
    e.onDrag(Offset(0, (best.y - p.y).clamp(-6.0, 6.0)));
  }
}
