import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/app_services.dart';
import '../../widgets/common/gravity_background.dart';
import '../../widgets/common/ui.dart';
import '../gameplay/gameplay_screen.dart';

class EndlessScreen extends StatelessWidget {
  const EndlessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(fit: StackFit.expand, children: [
        const GravityBackground(world: 8, dim: 0.6),
        SafeArea(
          child: ListenableBuilder(
            listenable: s.progress,
            builder: (context, _) {
              final d = s.progress.data;
              return ListView(padding: EdgeInsets.zero, children: [
                ScreenHeader(title: 'Endless', trailing: CoinPill(coins: s.progress.coins, compact: true)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SizedBox(height: 8),
                    const GlassCard(
                      padding: EdgeInsets.all(22),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.all_inclusive_rounded, color: AppColors.brand2, size: 34),
                        SizedBox(height: 10),
                        Text('How far can you fall?', style: AppText.title),
                        SizedBox(height: 6),
                        Text(
                            'A never-ending track built from every mechanic you have unlocked. It gets faster and trickier the further you go.',
                            style: AppText.bodyDim),
                      ]),
                    ),
                    const SectionLabel('Records'),
                    GlassCard(
                      child: Column(children: [
                        _row(Icons.emoji_events_rounded, 'Best score', '${d.endlessBestScore}'),
                        _row(Icons.straighten_rounded, 'Best distance', '${d.endlessBestDistance} m'),
                        _row(Icons.bolt_rounded, 'Best combo', 'x${d.endlessBestCombo}'),
                        _row(Icons.replay_rounded, 'Runs', '${d.endlessRuns}'),
                      ]),
                    ),
                    const SizedBox(height: 22),
                    PrimaryButton(
                      label: 'Start Run',
                      icon: Icons.play_arrow_rounded,
                      onTap: () => Navigator.of(context).push(fadeRoute(const GameplayScreen(request: RunRequest.endless()))),
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

  Widget _row(IconData i, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Icon(i, color: AppColors.textDim, size: 20),
          const SizedBox(width: 10),
          Text(k, style: AppText.body),
          const Spacer(),
          Text(v, style: AppText.number.copyWith(fontSize: 16)),
        ]),
      );
}
