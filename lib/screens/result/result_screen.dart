import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../game/systems/objective_system.dart';
import '../../game/systems/scoring.dart';
import '../../levels/models/level_config.dart';
import '../../progression/progress_controller.dart';
import '../../services/app_services.dart';
import '../../services/audio/audio_service.dart';
import '../../widgets/common/ui.dart';

/// "LEVEL COMPLETE" summary. Never auto-advances: the player chooses.
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.title,
    required this.stats,
    required this.reward,
    required this.config,
    required this.onNext,
    required this.onRetry,
    required this.onHome,
    this.onDoubleCoins,
    this.nextLabel = 'Next Level',
  });

  final String title;
  final RunStats stats;
  final RunReward reward;
  final LevelConfig config;
  final VoidCallback? onNext;
  final VoidCallback onRetry;
  final VoidCallback onHome;
  final Future<void> Function()? onDoubleCoins;
  final String nextLabel;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward();
  bool _doubling = false;

  @override
  void initState() {
    super.initState();
    // Star pops with sound.
    for (var i = 0; i < widget.reward.stars; i++) {
      Future.delayed(Duration(milliseconds: 450 + i * 260), () {
        if (mounted) AppScope.of(context).audio.play(Sfx.perfect, volume: 0.6 + i * 0.2);
      });
    }
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  Animation<double> _interval(double a, double b, [Curve c = Curves.easeOutBack]) =>
      CurvedAnimation(parent: _in, curve: Interval(a, b, curve: c));

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    final r = widget.reward;
    final isLevel = widget.config.kind == RunKind.level;
    return Material(
      color: AppColors.bgDeep.withOpacity(0.92),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                FadeTransition(
                  opacity: _interval(0, 0.25, Curves.easeOut),
                  child: Text(widget.title, style: AppText.label.copyWith(color: AppColors.textDim, letterSpacing: 2)),
                ),
                const SizedBox(height: 6),
                ScaleTransition(
                  scale: _interval(0.0, 0.3),
                  child: Text('LEVEL COMPLETE', textAlign: TextAlign.center, style: AppText.display.copyWith(fontSize: 34)),
                ),
                const SizedBox(height: 18),
                if (isLevel)
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < 3; i++)
                      ScaleTransition(
                        scale: _interval(0.25 + i * 0.15, 0.55 + i * 0.15, Curves.elasticOut),
                        child: Padding(
                          padding: EdgeInsets.only(left: 6, right: 6, bottom: i == 1 ? 14 : 0),
                          child: Icon(Icons.star_rounded,
                              size: i == 1 ? 76 : 60, color: i < r.stars ? AppColors.star : AppColors.locked),
                        ),
                      ),
                  ]),
                const SizedBox(height: 8),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: s.score.toDouble()),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => Text('${v.round()}', style: AppText.display.copyWith(fontSize: 46)),
                ),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('SCORE', style: AppText.label),
                  if (r.newBest) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration:
                          BoxDecoration(color: AppColors.success.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                      child: Text('NEW BEST', style: AppText.label.copyWith(color: AppColors.success, fontSize: 10)),
                    ),
                  ],
                ]),
                const SizedBox(height: 16),
                FadeTransition(
                  opacity: _interval(0.4, 0.7, Curves.easeOut),
                  child: GlassCard(
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const CoinIcon(size: 24),
                        const SizedBox(width: 8),
                        TweenAnimationBuilder<double>(
                          tween: Tween(end: r.coins.toDouble()),
                          duration: const Duration(milliseconds: 900),
                          builder: (_, v, __) => Text('+${v.round()}', style: AppText.title.copyWith(color: AppColors.coin)),
                        ),
                        if (r.doubled) ...[
                          const SizedBox(width: 8),
                          Text('×2', style: AppText.heading.copyWith(color: AppColors.coin)),
                        ],
                      ]),
                      const SizedBox(height: 14),
                      _StatGrid(items: [
                        ('Color matches', '${s.colorMatches}'),
                        ('Merges', '${s.merges}'),
                        ('Gravity shifts', '${s.gravityShifts}'),
                        ('Perfect actions', '${s.perfectActions}'),
                        ('Best combo', 'x${s.maxCombo}'),
                        ('Hits', '${s.hits}'),
                      ]),
                      if (isLevel && widget.config.starObjectives.isNotEmpty) ...[
                        const Divider(height: 26, color: AppColors.stroke),
                        const _ObjectiveLine(text: 'Complete the level', done: true),
                        for (final o in widget.config.starObjectives)
                          _ObjectiveLine(text: o.describe(), done: ObjectiveSystem.met(o, s)),
                      ],
                    ]),
                  ),
                ),
                if (r.missions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final m in r.missions)
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 700),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: AppColors.success.withOpacity(0.5),
                          child: Row(children: [
                            Icon(m.metric.icon, color: AppColors.success),
                            const SizedBox(width: 10),
                            Expanded(child: Text('Mission complete · ${m.title}', style: AppText.body)),
                            Text('Claim on Home', style: AppText.label.copyWith(color: AppColors.coin, fontSize: 10)),
                          ]),
                        ),
                      ),
                    ),
                ],
                if (r.unlocked.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final a in r.unlocked)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: AppColors.star.withOpacity(0.5),
                        child: Row(children: [
                          Icon(a.icon, color: AppColors.star),
                          const SizedBox(width: 10),
                          Expanded(child: Text('Achievement · ${a.title}', style: AppText.body)),
                          Text('+${a.reward}', style: AppText.body.copyWith(color: AppColors.coin)),
                        ]),
                      ),
                    ),
                ],
                const SizedBox(height: 18),
                if (widget.onNext != null)
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 900),
                    child: PrimaryButton(label: widget.nextLabel, icon: Icons.play_arrow_rounded, onTap: widget.onNext),
                  ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: SecondaryButton(label: 'Retry', icon: Icons.replay_rounded, onTap: widget.onRetry)),
                  const SizedBox(width: 10),
                  Expanded(child: SecondaryButton(label: 'Home', icon: Icons.home_rounded, onTap: widget.onHome)),
                ]),
                if (widget.onDoubleCoins != null && !r.doubled && r.coins > 0) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _doubling
                        ? null
                        : () async {
                            setState(() => _doubling = true);
                            await widget.onDoubleCoins!();
                            if (mounted) setState(() => _doubling = false);
                          },
                    icon: const Icon(Icons.ondemand_video_rounded, color: AppColors.coin),
                    label: Text('Watch ad · Double coins', style: AppText.body.copyWith(color: AppColors.coin)),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.items});
  final List<(String, String)> items;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 12) / 2;
      return Wrap(spacing: 12, runSpacing: 10, children: [
        for (final (k, v) in items)
          SizedBox(
            width: w,
            child: Row(children: [
              Expanded(child: Text(k, style: AppText.bodyDim, overflow: TextOverflow.ellipsis)),
              Text(v, style: AppText.number.copyWith(fontSize: 15)),
            ]),
          ),
      ]);
    });
  }
}

class _ObjectiveLine extends StatelessWidget {
  const _ObjectiveLine({required this.text, required this.done});
  final String text;
  final bool done;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(done ? Icons.star_rounded : Icons.star_border_rounded,
              size: 18, color: done ? AppColors.star : AppColors.textMute),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: done ? AppText.body : AppText.bodyDim)),
        ]),
      );
}
