import 'package:color_gravity/core/theme/app_theme.dart';
import 'package:color_gravity/game/systems/scoring.dart';
import 'package:color_gravity/levels/generators/level_generator.dart';
import 'package:color_gravity/progression/progress_controller.dart';
import 'package:color_gravity/screens/failure/failure_screen.dart';
import 'package:color_gravity/screens/gameplay/gameplay_screen.dart';
import 'package:color_gravity/screens/home/home_screen.dart';
import 'package:color_gravity/screens/level_map/level_map_screen.dart';
import 'package:color_gravity/screens/result/result_screen.dart';
import 'package:color_gravity/screens/settings/settings_screen.dart';
import 'package:color_gravity/services/app_services.dart';
import 'package:flutter/material.dart';
import 'package:color_gravity/core/constants/app_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records URLs and reports "could not open" (as if offline).
class FakeLauncher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final List<String> opened = [];
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> canLaunch(String url) async => false;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return false;
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;
}

Widget wrap(Widget child, AppServices s) => AppScope(services: s, child: MaterialApp(theme: AppTheme.build(), home: child));

Future<void> phone(WidgetTester t) async {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.75;
  addTearDown(t.view.reset);
}

/// Lets entrance animations / delayed futures finish.
Future<void> settle(WidgetTester t, [int ms = 2500]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('Home shows the play button and every mode', (t) async {
    await phone(t);
    final s = AppServices.offline();
    await t.pumpWidget(wrap(const HomeScreen(), s));
    await settle(t);
    expect(find.text('PLAY'), findsOneWidget);
    for (final label in ['Levels', 'Daily', 'Endless', 'Skins', 'Achievements']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('EASY'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Level map lists worlds and opens a level sheet', (t) async {
    await phone(t);
    final s = AppServices.offline();
    s.progress.recordLevel(level: 1, completed: true, stars: 3, stats: RunStats(), baseReward: 10);
    await t.pumpWidget(wrap(const LevelMapScreen(), s));
    await settle(t);
    expect(find.text('Levels'), findsOneWidget);
    expect(find.text('Color Valley'), findsOneWidget);
    await t.tap(find.text('2').first);
    await settle(t, 1200);
    expect(find.text('Level 2'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Gameplay HUD renders, pauses and resumes', (t) async {
    await phone(t);
    final s = AppServices.offline();
    await t.pumpWidget(wrap(const GameplayScreen(request: RunRequest.level(5)), s));
    await settle(t, 2500);
    expect(find.text('LEVEL 5'), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Gravity')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Your color')), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Pause'));
    await settle(t, 600);
    expect(find.text('PAUSED'), findsOneWidget);
    await t.tap(find.text('Resume'));
    await settle(t, 600);
    expect(find.text('PAUSED'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('Result screen shows stars, stats and choices (no auto-advance)', (t) async {
    await phone(t);
    final s = AppServices.offline();
    final level = LevelGenerator.load(12);
    var next = 0, retry = 0;
    final stats = RunStats()
      ..score = 1234
      ..colorMatches = 9
      ..merges = 3
      ..gravityShifts = 11;
    await t.pumpWidget(wrap(
      ResultScreen(
        title: 'LEVEL 12',
        stats: stats,
        reward: RunReward(coins: 40, stars: 2, previousStars: 0, firstClear: true, newBest: true, unlocked: const []),
        config: level.config,
        onNext: () => next++,
        onRetry: () => retry++,
        onHome: () {},
      ),
      s,
    ));
    await settle(t, 2500);
    expect(find.text('LEVEL COMPLETE'), findsOneWidget);
    expect(find.text('1234'), findsOneWidget);
    expect(find.text('NEW BEST'), findsOneWidget);
    expect(find.text('Gravity shifts'), findsOneWidget);
    await t.tap(find.text('Next Level'));
    await t.tap(find.text('Retry'));
    expect(next, 1);
    expect(retry, 1);
  });

  testWidgets('Failure screen shows reason and actions', (t) async {
    await phone(t);
    final s = AppServices.offline();
    final stats = RunStats()
      ..score = 300
      ..failReason = 'Wrong color at a gate';
    var retried = false;
    await t.pumpWidget(wrap(
      FailureScreen(stats: stats, progress: 0.4, onRetry: () => retried = true, onHome: () {}),
      s,
    ));
    await settle(t, 1500);
    expect(find.text('RUN FAILED'), findsOneWidget);
    expect(find.text('Wrong color at a gate'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('Watch Ad & Continue'), findsNothing, reason: 'continue is optional, never forced');
    await t.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('Settings: toggles, two INR Ads-Free plans, contact email, no Terms', (t) async {
    await phone(t);
    final s = AppServices.offline();
    await t.pumpWidget(wrap(const SettingsScreen(), s));
    await settle(t, 1500);
    expect(find.text('Music'), findsOneWidget);
    await t.tap(find.text('Music'));
    await t.pump();
    expect(s.settings.music, isFalse);

    expect(find.text('1 Month Ads-Free'), findsOneWidget);
    expect(find.text('Lifetime Ads-Free'), findsOneWidget);
    expect(find.text('₹299'), findsOneWidget);
    expect(find.text('₹2,999'), findsOneWidget);
    expect(find.textContaining(r'$'), findsNothing);
    expect(find.text('Restore Purchases'), findsOneWidget);

    await t.scrollUntilVisible(find.text('Contact Us'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('aakashmangukiya10@gmail.com'), findsOneWidget);
    expect(find.textContaining('Terms'), findsNothing);
    await t.scrollUntilVisible(find.text('Privacy Policy'), 200, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(find.text('Privacy Policy'));
    await t.pump();
    final launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    await t.tap(find.text('Privacy Policy'));
    await settle(t, 1500);
    expect(launcher.opened, [AppConfig.privacyPolicyUrl]);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Advertising', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('Terms'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('Home missions card opens the claim sheet', (t) async {
    await phone(t);
    final s = AppServices.offline();
    await t.pumpWidget(wrap(const HomeScreen(), s));
    await settle(t);
    expect(find.text('Daily Missions'), findsOneWidget);
    await t.tap(find.text('Daily Missions'));
    await settle(t, 1200);
    expect(find.text('New missions every day'), findsOneWidget);
    expect(find.text('Complete all 3 · bonus'), findsOneWidget);
    for (final m in s.progress.todaysMissions) {
      expect(find.text(m.title), findsOneWidget);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('Failure screen offers Retry from Checkpoint when one was reached', (t) async {
    await phone(t);
    final s = AppServices.offline();
    var fromCp = false, restart = false;
    await t.pumpWidget(wrap(
      FailureScreen(
        stats: RunStats()..failReason = 'Hit the spikes',
        progress: 0.7,
        onRetry: () => restart = true,
        onRetryCheckpoint: () => fromCp = true,
        onHome: () {},
      ),
      s,
    ));
    await settle(t, 1200);
    await t.tap(find.text('Retry from Checkpoint'));
    await t.tap(find.text('Restart Level'));
    expect(fromCp, isTrue);
    expect(restart, isTrue);
  });
}
