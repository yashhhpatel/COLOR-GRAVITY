import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../progression/daily_missions.dart';
import '../../progression/progress_controller.dart';
import '../../services/app_services.dart';
import '../../services/audio/audio_service.dart';
import '../../services/haptics/haptics_service.dart';
import '../../widgets/common/ui.dart';

/// Compact Home card: today's mission progress + claim badge.
class MissionsCard extends StatelessWidget {
  const MissionsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).progress;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final missions = p.todaysMissions;
        final done = missions.where(p.missionDone).length;
        final claimable = p.claimableMissions;
        return Pressable(
          onTap: () => showMissionsSheet(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface.withOpacity(0.88),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: claimable > 0 ? AppColors.coin.withOpacity(0.7) : AppColors.stroke),
            ),
            child: Row(children: [
              const Icon(Icons.task_alt_rounded, color: AppColors.text),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Daily Missions', style: AppText.body.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  AnimatedBar(value: done / missions.length, height: 5, color: AppColors.success),
                ]),
              ),
              const SizedBox(width: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
                child: claimable > 0
                    ? _PulsingBadge(key: ValueKey('c$claimable'), text: 'CLAIM $claimable')
                    : Text('$done/${missions.length}', key: ValueKey('d$done'), style: AppText.number.copyWith(fontSize: 15)),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _PulsingBadge extends StatefulWidget {
  const _PulsingBadge({super.key, required this.text});
  final String text;
  @override
  State<_PulsingBadge> createState() => _PulsingBadgeState();
}

class _PulsingBadgeState extends State<_PulsingBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: Tween(begin: 1.0, end: 1.08).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: AppColors.coin, borderRadius: BorderRadius.circular(14)),
          child: Text(widget.text, style: AppText.label.copyWith(color: AppColors.bg, fontSize: 11)),
        ),
      );
}

Future<void> showMissionsSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _MissionsSheet(),
    );

class _MissionsSheet extends StatelessWidget {
  const _MissionsSheet();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = s.progress;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final missions = p.todaysMissions;
        final all = p.allMissionsDone;
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(20, 14, 20, 22 + MediaQuery.of(context).padding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.strokeStrong, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            const Text('Daily Missions', style: AppText.title),
            const SizedBox(height: 2),
            const Text('New missions every day', style: AppText.label),
            const SizedBox(height: 14),
            for (var i = 0; i < missions.length; i++)
              FadeSlideIn(
                delay: FadeSlideIn.stagger(i, stepMs: 70),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MissionTile(mission: missions[i], progress: p),
                ),
              ),
            const SizedBox(height: 4),
            FadeSlideIn(
              delay: const Duration(milliseconds: 240),
              child: _ClaimRow(
                icon: Icons.workspace_premium_rounded,
                title: 'Complete all 3',
                reward: DailyMissions.allDoneBonus,
                ready: all && !p.data.missionBonusClaimed,
                claimed: p.data.missionBonusClaimed,
                onClaim: () => p.claimMissionBonus(),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _MissionTile extends StatelessWidget {
  const _MissionTile({required this.mission, required this.progress});
  final DailyMission mission;
  final ProgressController progress;

  @override
  Widget build(BuildContext context) {
    final cur = progress.missionProgress(mission).clamp(0, mission.target);
    final done = progress.missionDone(mission);
    final claimed = progress.missionClaimed(mission);
    return GlassCard(
      color: AppColors.surfaceHigh,
      border: done && !claimed ? AppColors.coin.withOpacity(0.6) : null,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration:
              BoxDecoration(shape: BoxShape.circle, color: (done ? AppColors.success : AppColors.brand2).withOpacity(0.16)),
          child: Icon(mission.metric.icon, size: 20, color: done ? AppColors.success : AppColors.brand2),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mission.title, style: AppText.body.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                  child: AnimatedBar(value: cur / mission.target, height: 5, color: done ? AppColors.success : AppColors.brand2)),
              const SizedBox(width: 8),
              Text('$cur/${mission.target}', style: AppText.label.copyWith(color: AppColors.text)),
            ]),
          ]),
        ),
        const SizedBox(width: 10),
        _ClaimButton(
          reward: mission.reward,
          ready: done && !claimed,
          claimed: claimed,
          onClaim: () => progress.claimMission(mission),
        ),
      ]),
    );
  }
}

class _ClaimRow extends StatelessWidget {
  const _ClaimRow(
      {required this.icon,
      required this.title,
      required this.reward,
      required this.ready,
      required this.claimed,
      required this.onClaim});
  final IconData icon;
  final String title;
  final int reward;
  final bool ready, claimed;
  final int Function() onClaim;

  @override
  Widget build(BuildContext context) => GlassCard(
        color: AppColors.coin.withOpacity(0.08),
        border: AppColors.coin.withOpacity(ready ? 0.7 : 0.25),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(icon, color: AppColors.coin),
          const SizedBox(width: 12),
          Expanded(child: Text('$title · bonus', style: AppText.body.copyWith(fontWeight: FontWeight.w600))),
          _ClaimButton(reward: reward, ready: ready, claimed: claimed, onClaim: onClaim),
        ]),
      );
}

/// Claim button with a "+coins" pop when pressed.
class _ClaimButton extends StatefulWidget {
  const _ClaimButton({required this.reward, required this.ready, required this.claimed, required this.onClaim});
  final int reward;
  final bool ready, claimed;
  final int Function() onClaim;
  @override
  State<_ClaimButton> createState() => _ClaimButtonState();
}

class _ClaimButtonState extends State<_ClaimButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _claim() {
    final got = widget.onClaim();
    if (got <= 0) return;
    final s = AppScope.of(context);
    s.audio.play(Sfx.reward);
    s.haptics.fire(Haptic.medium);
    _pop.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
        child: widget.claimed
            ? const Icon(Icons.check_circle_rounded, key: ValueKey('done'), color: AppColors.success, size: 28)
            : Pressable(
                key: const ValueKey('claim'),
                onTap: widget.ready ? _claim : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: widget.ready ? AppColors.coin : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: widget.ready ? AppColors.coin : AppColors.stroke),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const CoinIcon(size: 14),
                    const SizedBox(width: 4),
                    Text('${widget.reward}',
                        style: AppText.number.copyWith(fontSize: 13, color: widget.ready ? AppColors.bg : AppColors.textDim)),
                  ]),
                ),
              ),
      ),
      // "+N" floats up after claiming.
      AnimatedBuilder(
        animation: _pop,
        builder: (_, __) {
          if (_pop.value == 0 || _pop.value == 1) return const SizedBox.shrink();
          final t = Curves.easeOut.transform(_pop.value);
          return Positioned(
            top: -18 - 26 * t,
            child: IgnorePointer(
              child: Opacity(
                opacity: (1 - _pop.value).clamp(0.0, 1.0),
                child: Text('+${widget.reward}', style: AppText.heading.copyWith(color: AppColors.coin)),
              ),
            ),
          );
        },
      ),
    ]);
  }
}
