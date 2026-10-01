import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../levels/generators/level_generator.dart';
import '../../levels/models/level_config.dart';
import '../../services/app_services.dart';
import '../../widgets/common/gravity_background.dart';
import '../../widgets/common/ui.dart';
import '../gameplay/gameplay_screen.dart';

class DailyScreen extends StatelessWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final today = DateTime.now();
    final daily = LevelGenerator.daily(today);
    final c = daily.config;
    final missions = c.objectives.where((o) => o.type != ObjectiveType.reachFinish);
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(fit: StackFit.expand, children: [
        GravityBackground(world: c.worldId, dim: 0.65),
        SafeArea(
          child: ListenableBuilder(
            listenable: s.progress,
            builder: (context, _) {
              final p = s.progress;
              final done = p.dailyDoneToday;
              return ListView(padding: EdgeInsets.zero, children: [
                ScreenHeader(title: 'Daily Challenge', trailing: CoinPill(coins: p.coins, compact: true)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SizedBox(height: 8),
                    GlassCard(
                      padding: const EdgeInsets.all(22),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${_month(today.month)} ${today.day}'.toUpperCase(),
                            style: AppText.label.copyWith(color: AppColors.brand2)),
                        const SizedBox(height: 6),
                        Text(c.modifier.title, style: AppText.display.copyWith(fontSize: 32)),
                        const SizedBox(height: 6),
                        Text(c.modifier.description, style: AppText.bodyDim),
                        const SizedBox(height: 16),
                        for (final m in missions)
                          Row(children: [
                            const Icon(Icons.flag_rounded, color: AppColors.star, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(m.describe(), style: AppText.body)),
                          ]),
                        const Row(children: [
                          Icon(Icons.card_giftcard_rounded, color: AppColors.coin, size: 18),
                          SizedBox(width: 8),
                          Expanded(child: Text('Reward: 100 coins + streak bonus', style: AppText.body)),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: _Stat(
                              icon: Icons.local_fire_department_rounded,
                              label: 'Streak',
                              value: '${p.currentStreak}',
                              color: const Color(0xFFFF8A4D))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _Stat(
                              icon: Icons.today_rounded,
                              label: 'Today best',
                              value: '${p.data.dailyBestDay == _key(today) ? p.data.dailyTodayBest : 0}')),
                      const SizedBox(width: 10),
                      Expanded(child: _Stat(icon: Icons.emoji_events_rounded, label: 'All-time', value: '${p.data.dailyBest}')),
                    ]),
                    const SizedBox(height: 22),
                    if (done)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.check_circle_rounded, color: AppColors.success),
                          const SizedBox(width: 8),
                          Text('Completed today · play again for a better score',
                              style: AppText.body.copyWith(color: AppColors.success)),
                        ]),
                      ),
                    PrimaryButton(
                      label: done ? 'Play Again' : 'Play Daily',
                      icon: Icons.play_arrow_rounded,
                      onTap: () => Navigator.of(context).push(fadeRoute(const GameplayScreen(request: RunRequest.daily()))),
                    ),
                    const SizedBox(height: 20),
                  ]),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }

  static int _key(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
  static String _month(int m) =>
      const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, this.color = AppColors.star});
  final IconData icon;
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Column(children: [
          Icon(icon, color: color),
          const SizedBox(height: 6),
          Text(value, style: AppText.number),
          Text(label, style: AppText.label.copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );
}
