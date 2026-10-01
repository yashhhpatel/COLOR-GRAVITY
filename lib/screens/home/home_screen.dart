import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/world_themes.dart';
import '../../levels/models/level_config.dart';
import '../../services/app_services.dart';
import '../../services/audio/audio_service.dart';
import '../../widgets/common/gravity_background.dart';
import '../../widgets/common/logo.dart';
import '../../widgets/common/ui.dart';
import '../achievements/achievements_screen.dart';
import '../cosmetics/cosmetics_screen.dart';
import '../daily/daily_screen.dart';
import '../endless/endless_screen.dart';
import '../gameplay/gameplay_screen.dart';
import '../level_map/level_map_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).audio.playMusic(MusicTrack.home);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _open(Widget page) => Navigator.of(context).push(fadeRoute(page)).then((_) {
        if (mounted) {
          AppScope.of(context).audio.playMusic(MusicTrack.home);
          setState(() {});
        }
      });

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: ListenableBuilder(
        listenable: s.progress,
        builder: (context, _) {
          final level = s.progress.unlockedLevel.clamp(1, AppConfig.totalLevels);
          final world = WorldTheme.forLevel(level);
          return Stack(fit: StackFit.expand, children: [
            GravityBackground(world: world.id),
            SafeArea(
              child: LayoutBuilder(builder: (context, c) {
                final compact = c.maxHeight < 640;
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Column(children: [
                        Row(children: [
                          CoinPill(coins: s.progress.coins),
                          const Spacer(),
                          IconCircleButton(
                            icon: Icons.emoji_events_rounded,
                            tooltip: 'Achievements',
                            onTap: () => _open(const AchievementsScreen()),
                          ),
                          const SizedBox(width: 10),
                          IconCircleButton(
                            icon: Icons.settings_rounded,
                            tooltip: 'Settings',
                            onTap: () => _open(const SettingsScreen()),
                          ),
                        ]),
                        SizedBox(height: compact ? 18 : 48),
                        FadeSlideIn(child: GameLogo(size: compact ? 0.82 : 1)),
                        SizedBox(height: compact ? 22 : 44),
                        Text('${world.name.toUpperCase()} · WORLD ${world.id + 1}',
                            style: AppText.label.copyWith(color: world.accent, letterSpacing: 1.6)),
                        const SizedBox(height: 6),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            transitionBuilder: (w, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: w)),
                            child: Text('Level $level', key: ValueKey(level), style: AppText.title),
                          ),
                          const SizedBox(width: 10),
                          TierBadge(
                              label: DifficultyTier.forLevel(level).label,
                              color: Color(DifficultyTier.forLevel(level).argb),
                              small: true),
                        ]),
                        const SizedBox(height: 18),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 120),
                          child: ScaleTransition(
                            scale:
                                Tween(begin: 1.0, end: 1.035).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                            child: PrimaryButton(
                              label: 'PLAY',
                              icon: Icons.play_arrow_rounded,
                              height: 72,
                              gradient: AppColors.playGradient,
                              onTap: () => _open(GameplayScreen(request: RunRequest.level(level))),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 220),
                          child: Row(children: [
                            Expanded(
                              child: _Tile(icon: Icons.map_rounded, label: 'Levels', onTap: () => _open(const LevelMapScreen())),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _Tile(
                                icon: Icons.today_rounded,
                                label: 'Daily',
                                badge: !s.progress.dailyDoneToday,
                                onTap: () => _open(const DailyScreen()),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _Tile(
                                  icon: Icons.all_inclusive_rounded, label: 'Endless', onTap: () => _open(const EndlessScreen())),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 10),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 300),
                          child: Row(children: [
                            Expanded(
                              child: _Tile(
                                  icon: Icons.auto_awesome_rounded, label: 'Skins', onTap: () => _open(const CosmeticsScreen())),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _Tile(
                                icon: Icons.emoji_events_outlined,
                                label: 'Achievements',
                                onTap: () => _open(const AchievementsScreen()),
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 12),
                      ]),
                    ),
                  ),
                );
              }),
            ),
          ]);
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap, this.badge = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 76,
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(0.88),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Stack(children: [
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: AppColors.text, size: 24),
              const SizedBox(height: 6),
              Text(label,
                  style: AppText.label.copyWith(color: AppColors.text, letterSpacing: 0.4, fontSize: 12.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (badge)
            Positioned(
              right: 12,
              top: 10,
              child: Container(
                  width: 9, height: 9, decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle)),
            ),
        ]),
      ),
    );
  }
}
