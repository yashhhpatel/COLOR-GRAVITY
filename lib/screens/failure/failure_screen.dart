import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../game/systems/scoring.dart';
import '../../widgets/common/ui.dart';

/// "RUN FAILED" (or "RUN OVER" in endless). Continue-by-ad is optional.
class FailureScreen extends StatefulWidget {
  const FailureScreen({
    super.key,
    required this.stats,
    required this.progress,
    required this.onRetry,
    required this.onHome,
    this.onContinue,
    this.onRetryCheckpoint,
    this.endless = false,
    this.bestScore,
    this.bestDistance,
  });

  final RunStats stats;
  final double progress;
  final VoidCallback onRetry;
  final VoidCallback onHome;
  final Future<void> Function()? onContinue;

  /// Hard / Very Hard levels: resume from the checkpoint that was reached.
  final VoidCallback? onRetryCheckpoint;
  final bool endless;
  final int? bestScore;
  final int? bestDistance;

  @override
  State<FailureScreen> createState() => _FailureScreenState();
}

class _FailureScreenState extends State<FailureScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  bool _busy = false;

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    final title = widget.endless ? 'RUN OVER' : 'RUN FAILED';
    final newBest = widget.endless && widget.bestScore != null && s.score > widget.bestScore!;
    return Material(
      color: AppColors.bgDeep.withOpacity(0.9),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: FadeTransition(
                opacity: _in,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
                      .animate(CurvedAnimation(parent: _in, curve: Curves.easeOutCubic)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.danger.withOpacity(0.15)),
                      child: Icon(widget.endless ? Icons.all_inclusive_rounded : Icons.close_rounded,
                          size: 38, color: AppColors.danger),
                    ),
                    const SizedBox(height: 14),
                    Text(title, style: AppText.display.copyWith(fontSize: 34)),
                    const SizedBox(height: 8),
                    if (s.failReason != null)
                      Text(s.failReason!, textAlign: TextAlign.center, style: AppText.body.copyWith(color: AppColors.textDim)),
                    const SizedBox(height: 18),
                    GlassCard(
                      child: Column(children: [
                        if (!widget.endless) ...[
                          Row(children: [
                            const Text('Progress', style: AppText.bodyDim),
                            const Spacer(),
                            Text('${(widget.progress * 100).round()}%', style: AppText.number.copyWith(fontSize: 15)),
                          ]),
                          const SizedBox(height: 8),
                          AnimatedBar(value: widget.progress),
                          const SizedBox(height: 14),
                        ],
                        _line('Score', '${s.score}'),
                        if (widget.endless) _line('Distance', '${s.distance.round()} m'),
                        _line('Gravity shifts', '${s.gravityShifts}'),
                        _line('Merges', '${s.merges}'),
                        _line('Color matches', '${s.colorMatches}'),
                        if (widget.endless) _line('Best combo', 'x${s.maxCombo}'),
                        if (widget.endless && widget.bestScore != null)
                          _line(newBest ? 'Previous best' : 'Best score', '${widget.bestScore}'),
                      ]),
                    ),
                    if (newBest) ...[
                      const SizedBox(height: 10),
                      Text('NEW BEST SCORE!', style: AppText.heading.copyWith(color: AppColors.success)),
                    ],
                    const SizedBox(height: 18),
                    if (widget.onRetryCheckpoint != null) ...[
                      PrimaryButton(label: 'Retry from Checkpoint', icon: Icons.flag_rounded, onTap: widget.onRetryCheckpoint),
                      const SizedBox(height: 10),
                      SecondaryButton(label: 'Restart Level', icon: Icons.replay_rounded, onTap: widget.onRetry),
                    ] else
                      PrimaryButton(label: 'Retry', icon: Icons.replay_rounded, onTap: widget.onRetry),
                    const SizedBox(height: 10),
                    SecondaryButton(label: 'Home', icon: Icons.home_rounded, onTap: widget.onHome),
                    if (widget.onContinue != null) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                setState(() => _busy = true);
                                await widget.onContinue!();
                                if (mounted) setState(() => _busy = false);
                              },
                        icon: const Icon(Icons.ondemand_video_rounded, color: AppColors.brand2),
                        label: Text('Watch Ad & Continue', style: AppText.body.copyWith(color: AppColors.brand2)),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
            children: [Text(k, style: AppText.bodyDim), const Spacer(), Text(v, style: AppText.number.copyWith(fontSize: 15))]),
      );
}
