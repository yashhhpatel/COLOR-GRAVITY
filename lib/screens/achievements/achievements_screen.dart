import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../progression/achievements.dart';
import '../../services/app_services.dart';
import '../../widgets/common/ui.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final d = s.progress.data;
    final done = Achievements.all.where((a) => d.achievements.contains(a.id)).length;
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: MenuBackdrop(
        child: SafeArea(
          child: Column(children: [
            ScreenHeader(
              title: 'Achievements',
              trailing: Text('$done/${Achievements.all.length}', style: AppText.number.copyWith(color: AppColors.textDim)),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: Achievements.all.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final a = Achievements.all[i];
                  final unlocked = d.achievements.contains(a.id);
                  final prog = a.progress(d);
                  return FadeSlideIn(
                    delay: FadeSlideIn.stagger(i),
                    child: GlassCard(
                      padding: const EdgeInsets.all(14),
                      border: unlocked ? AppColors.star.withOpacity(0.45) : null,
                      child: Row(children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: unlocked ? AppColors.star.withOpacity(0.18) : AppColors.surfaceHigh,
                          ),
                          child: Icon(a.icon, color: unlocked ? AppColors.star : AppColors.textMute),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.title, style: AppText.heading.copyWith(fontSize: 16)),
                            const SizedBox(height: 2),
                            Text(a.description, style: AppText.bodyDim.copyWith(fontSize: 13)),
                            const SizedBox(height: 8),
                            AnimatedBar(value: prog / a.target, height: 5, color: unlocked ? AppColors.star : AppColors.brand2),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        Column(children: [
                          if (unlocked)
                            const Icon(Icons.check_circle_rounded, color: AppColors.success)
                          else
                            Text('$prog/${a.target}', style: AppText.label.copyWith(color: AppColors.text)),
                          const SizedBox(height: 4),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            const CoinIcon(size: 13),
                            const SizedBox(width: 3),
                            Text('${a.reward}', style: AppText.label.copyWith(color: AppColors.coin)),
                          ]),
                        ]),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
