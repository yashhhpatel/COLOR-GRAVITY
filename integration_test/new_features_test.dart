import 'dart:io';

import 'package:color_gravity/core/theme/app_theme.dart';
import 'package:color_gravity/game/engine/game_engine.dart';
import 'package:color_gravity/game/entities/entity.dart';
import 'package:color_gravity/screens/gameplay/gameplay_screen.dart';
import 'package:color_gravity/screens/gameplay/hud.dart';
import 'package:color_gravity/screens/home/home_screen.dart';
import 'package:color_gravity/services/app_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// On-device checks for: daily missions, checkpoints, hit feedback,
/// flying coins and the combo timer ring. Screenshots are saved to the
/// app's temp dir (pulled afterwards with adb).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final results = <String, Object>{};

  Future<void> shot(String name) async {
    try {
      await binding.convertFlutterSurfaceToImage();
      final bytes = await binding.takeScreenshot(name);
      final dir = await getTemporaryDirectory();
      await File('${dir.path}/$name.png').writeAsBytes(bytes);
    } catch (e) {
      results['screenshot_$name'] = 'failed: $e';
    }
  }

  Future<void> frames(WidgetTester t, int ms) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('daily missions: card, sheet and claim', (t) async {
    final s = AppServices.offline();
    final m = s.progress.todaysMissions.first;
    s.progress.data.missionProgress[m.id] = m.target; // pretend it was completed today
    await t.pumpWidget(AppScope(services: s, child: MaterialApp(theme: AppTheme.build(), home: const HomeScreen())));
    await frames(t, 2500);
    expect(find.text('Daily Missions'), findsOneWidget);
    expect(find.text('CLAIM 1'), findsOneWidget);
    await shot('01_home_missions_card');

    await t.tap(find.text('Daily Missions'));
    await frames(t, 1200);
    expect(find.text(m.title), findsOneWidget);
    await shot('02_missions_sheet');

    final coins = s.progress.coins;
    final claim = find.descendant(
      of: find.ancestor(of: find.text(m.title), matching: find.byType(Row)).first,
      matching: find.text('${m.reward}'),
    );
    await t.tap(claim.first);
    await frames(t, 400);
    await shot('03_mission_claimed');
    expect(s.progress.missionClaimed(m), isTrue);
    expect(s.progress.coins, coins + m.reward);
    await frames(t, 800);
    expect(find.byIcon(Icons.check_circle_rounded), findsWidgets);
    results['missions'] = 'claimed "${m.title}" +${m.reward} coins';
  });

  testWidgets('checkpoint → fail → Retry from Checkpoint, with hit/coin/combo feedback', (t) async {
    final s = AppServices.offline();
    await t.pumpWidget(AppScope(
      services: s,
      child: MaterialApp(theme: AppTheme.build(), home: const GameplayScreen(request: RunRequest.level(450))),
    ));
    await frames(t, 1600);
    final e = GameplayScreen.debugEngine!;
    expect(e.level.plan.ofKind(EntityKind.checkpoint), isNotEmpty);

    var maxFlyers = 0, ringSeen = false, sec = 0.0;
    var cpShot = false;
    // Invulnerable autopilot until the checkpoint is passed.
    while (e.checkpoint == null && sec < 90) {
      e.player.invuln = 2;
      _steerToCoins(e);
      await t.pump(const Duration(milliseconds: 33));
      sec += 0.033;
      final flyers = find.byType(FlyingCoin).evaluate().length;
      if (flyers > maxFlyers) maxFlyers = flyers;
      if (e.hud.comboTime.value > 0 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty) ringSeen = true;
      if (flyers > 0 && !cpShot) {
        cpShot = true;
        await shot('04_coins_flying_to_hud');
      }
    }
    expect(e.checkpoint, isNotNull, reason: 'checkpoint reached');
    await frames(t, 200);
    await shot('05_checkpoint_passed');
    final cp = e.checkpoint!;

    // Now play without protection and without steering until a heart is lost.
    e.player.invuln = 0;
    final pulse0 = e.hud.hitPulse.value;
    sec = 0;
    while (e.hud.hitPulse.value == pulse0 && e.phase == RunPhase.playing && sec < 60) {
      await t.pump(const Duration(milliseconds: 33));
      sec += 0.033;
    }
    expect(e.hud.hitPulse.value, greaterThan(pulse0), reason: 'a hit happened');
    await t.pump(const Duration(milliseconds: 60));
    await shot('06_hit_vignette_heart_shake');

    // Lose the remaining hearts quickly.
    e.player.hearts = 1;
    sec = 0;
    while (e.phase == RunPhase.playing && sec < 60) {
      if (e.player.invuln > 0.2) e.player.invuln = 0.2;
      await t.pump(const Duration(milliseconds: 33));
      sec += 0.033;
    }
    expect(e.phase, RunPhase.failed);
    await frames(t, 1500);
    expect(find.text('Retry from Checkpoint'), findsOneWidget);
    expect(find.text('Restart Level'), findsOneWidget);
    await shot('07_failure_retry_from_checkpoint');

    await t.tap(find.text('Retry from Checkpoint'));
    await frames(t, 600);
    final r = GameplayScreen.debugEngine!;
    expect(identical(r, e), isFalse);
    expect(r.resumed, isTrue);
    expect(find.text('FROM CHECKPOINT'), findsOneWidget);
    await shot('08_resumed_from_checkpoint');
    expect(r.stats.score, cp.stats.score);
    expect(r.player.hearts, r.config.hearts, reason: 'hearts refilled');
    final before = r.level.plan.entities.where((x) => x.trackY <= cp.track).length;
    await frames(t, 1500);
    expect(r.entities.where((x) => x.trackY <= cp.track), isEmpty, reason: 'nothing before the checkpoint respawns');

    results['checkpoint'] = 'track ${cp.track.round()}, resumed score ${r.stats.score}, skipped $before earlier objects';
    results['flyingCoinsMaxOnScreen'] = maxFlyers;
    results['comboRingSeen'] = ringSeen;
    results['hitPulses'] = e.hud.hitPulse.value;
    expect(maxFlyers, greaterThan(0), reason: 'coins flew to the HUD');
    binding.reportData = results;
    // ignore: avoid_print
    print('FEATURE_REPORT $results');
  });
}

void _steerToCoins(GameEngine e) {
  final p = e.player;
  Entity? best;
  var bestD = double.infinity;
  for (final x in e.entities) {
    final good = x.kind == EntityKind.coin || (x.kind == EntityKind.orb && e.colors.canCollect(p.color, x));
    if (!good || x.y > p.y + 10 || x.y < p.y - 300) continue;
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
