import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/world_themes.dart';
import '../../levels/generators/level_generator.dart';
import '../../levels/models/level_config.dart';
import '../../services/app_services.dart';
import '../../widgets/common/ui.dart';
import '../gameplay/gameplay_screen.dart';

/// Scrollable map of all 1000 levels across 10 worlds (lazy rows).
class LevelMapScreen extends StatefulWidget {
  const LevelMapScreen({super.key});
  @override
  State<LevelMapScreen> createState() => _LevelMapScreenState();
}

class _LevelMapScreenState extends State<LevelMapScreen> {
  static const int perRow = 5;
  static const double rowH = 92;
  static const double headerH = 132;
  static int _lastSeenUnlocked = 0;
  late final ScrollController _scroll;
  int? _celebrate;

  int get _rowsPerWorld => AppConfig.levelsPerWorld ~/ perRow;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final unlocked = AppScope.of(context).progress.unlockedLevel;
    if (_lastSeenUnlocked != 0 && unlocked > _lastSeenUnlocked) _celebrate = unlocked;
    _lastSeenUnlocked = unlocked;
  }

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final lvl = AppScope.of(context).progress.unlockedLevel;
      final world = (lvl - 1) ~/ AppConfig.levelsPerWorld;
      final row = ((lvl - 1) % AppConfig.levelsPerWorld) ~/ perRow;
      final offset =
          world * (headerH + _rowsPerWorld * rowH) + headerH + row * rowH - _scroll.position.viewportDimension / 2 + rowH / 2;
      _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _openLevel(int level) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _LevelSheet(
          level: level,
          onPlay: (shield) {
            Navigator.of(context).pop();
            Navigator.of(context).push(fadeRoute(GameplayScreen(request: RunRequest.level(level, withShield: shield)))).then((_) {
              if (mounted) setState(() {});
            });
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: MenuBackdrop(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: s.progress,
            builder: (context, _) {
              final data = s.progress.data;
              return Column(children: [
                ScreenHeader(title: 'Levels', trailing: CoinPill(coins: s.progress.coins, compact: true)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(children: [
                    const Icon(Icons.star_rounded, color: AppColors.star, size: 18),
                    const SizedBox(width: 4),
                    Text('${data.totalStars} / ${AppConfig.totalLevels * 3}',
                        style: AppText.label.copyWith(color: AppColors.text)),
                    const Spacer(),
                    Text('${data.levelsCompleted} cleared', style: AppText.label),
                  ]),
                ),
                Expanded(
                  child: CustomScrollView(
                    controller: _scroll,
                    slivers: [
                      for (var w = 0; w < 10; w++) ...[
                        SliverToBoxAdapter(
                            child: _WorldHeader(
                                world: WorldTheme.byId(w), unlockedLevel: s.progress.unlockedLevel, stars: data.stars)),
                        SliverFixedExtentList(
                          itemExtent: rowH,
                          delegate: SliverChildBuilderDelegate(
                            (context, row) => _LevelRow(
                              world: w,
                              row: row,
                              unlocked: s.progress.unlockedLevel,
                              starsFor: data.starsFor,
                              celebrate: _celebrate,
                              onTap: _openLevel,
                            ),
                            childCount: _rowsPerWorld,
                          ),
                        ),
                      ],
                      const SliverToBoxAdapter(child: SizedBox(height: 40)),
                    ],
                  ),
                ),
                if (s.monetization.ads.banner(adsRemoved: s.monetization.adsRemoved) case final b?)
                  SafeArea(top: false, child: b),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

class _WorldHeader extends StatelessWidget {
  const _WorldHeader({required this.world, required this.unlockedLevel, required this.stars});

  static List<DifficultyTier> _tiers(int first) => {
        DifficultyTier.forLevel(first),
        DifficultyTier.forLevel(first + AppConfig.levelsPerWorld - 1),
      }.toList();
  final WorldTheme world;
  final int unlockedLevel;
  final List<int> stars;

  @override
  Widget build(BuildContext context) {
    final first = world.id * AppConfig.levelsPerWorld + 1;
    final locked = unlockedLevel < first;
    var got = 0;
    for (var i = first - 1; i < first - 1 + AppConfig.levelsPerWorld && i < stars.length; i++) {
      got += stars[i];
    }
    return SizedBox(
      height: _LevelMapScreenState.headerH,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(colors: [world.top, world.bottom], begin: Alignment.topLeft, end: Alignment.bottomRight),
            border: Border.all(color: world.accent.withOpacity(locked ? 0.15 : 0.45)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('WORLD ${world.id + 1}', style: AppText.label.copyWith(color: world.accent)),
                const SizedBox(height: 4),
                Text(world.name, style: AppText.title.copyWith(fontSize: 21)),
                const SizedBox(height: 6),
                Row(children: [
                  for (final t in _tiers(first)) ...[
                    TierBadge(label: t.label, color: Color(t.argb), small: true),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(world.tagline,
                        style: AppText.bodyDim.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ]),
            ),
            if (locked)
              const Icon(Icons.lock_rounded, color: AppColors.textMute)
            else
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.star_rounded, color: AppColors.star),
                Text('$got/${AppConfig.levelsPerWorld * 3}', style: AppText.label.copyWith(color: AppColors.text)),
              ]),
          ]),
        ),
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.world,
    required this.row,
    required this.unlocked,
    required this.starsFor,
    required this.celebrate,
    required this.onTap,
  });
  final int world, row, unlocked;
  final int Function(int) starsFor;
  final int? celebrate;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    const perRow = _LevelMapScreenState.perRow;
    final reversed = row.isOdd; // snake path
    final theme = WorldTheme.byId(world);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth - 32;
      return Stack(children: [
        // Path line connecting nodes
        Positioned.fill(
          child:
              CustomPaint(painter: _PathPainter(reversed: reversed, color: theme.accent.withOpacity(0.18), lastRow: row == 19)),
        ),
        for (var i = 0; i < perRow; i++)
          Builder(builder: (_) {
            final idx = reversed ? perRow - 1 - i : i;
            final level = world * AppConfig.levelsPerWorld + row * perRow + idx + 1;
            final x = 16 + w * (i + 0.5) / perRow;
            final wave = math.sin((row * perRow + i) * 0.9) * 6;
            return Positioned(
              left: x - 30,
              top: 12 + wave,
              child: _LevelNode(
                level: level,
                stars: starsFor(level),
                state: level < unlocked
                    ? _NodeState.done
                    : level == unlocked
                        ? _NodeState.current
                        : _NodeState.locked,
                accent: theme.accent,
                celebrate: celebrate == level,
                onTap: level <= unlocked ? () => onTap(level) : null,
              ),
            );
          }),
      ]);
    });
  }
}

class _PathPainter extends CustomPainter {
  _PathPainter({required this.reversed, required this.color, required this.lastRow});
  final bool reversed;
  final Color color;
  final bool lastRow;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const y = 42.0;
    final w = size.width - 32;
    canvas.drawLine(Offset(16 + w * 0.1, y), Offset(16 + w * 0.9, y), p);
    if (!lastRow) {
      final x = reversed ? 16 + w * 0.1 : 16 + w * 0.9;
      canvas.drawLine(Offset(x, y), Offset(x, size.height + 42), p);
    }
  }

  @override
  bool shouldRepaint(covariant _PathPainter old) => old.reversed != reversed || old.color != color;
}

enum _NodeState { locked, current, done }

class _LevelNode extends StatefulWidget {
  const _LevelNode(
      {required this.level, required this.stars, required this.state, required this.accent, required this.celebrate, this.onTap});
  final int level, stars;
  final _NodeState state;
  final Color accent;
  final bool celebrate;
  final VoidCallback? onTap;
  @override
  State<_LevelNode> createState() => _LevelNodeState();
}

class _LevelNodeState extends State<_LevelNode> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.state == _NodeState.current) {
      _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final isCurrent = st == _NodeState.current;
    Widget node = Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      child: Container(
        width: isCurrent ? 56 : 50,
        height: isCurrent ? 56 : 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: st == _NodeState.locked
              ? null
              : isCurrent
                  ? AppColors.playGradient
                  : LinearGradient(colors: [widget.accent.withOpacity(0.55), widget.accent.withOpacity(0.25)]),
          color: st == _NodeState.locked ? AppColors.surface : null,
          border: Border.all(
              color: st == _NodeState.locked ? AppColors.stroke : Colors.white.withOpacity(isCurrent ? 0.9 : 0.35),
              width: isCurrent ? 2.5 : 1.5),
          boxShadow: isCurrent ? [BoxShadow(color: AppColors.brand.withOpacity(0.55), blurRadius: 18)] : null,
        ),
        child: st == _NodeState.locked
            ? const Icon(Icons.lock_rounded, size: 18, color: AppColors.textMute)
            : Text('${widget.level}', style: AppText.number.copyWith(fontSize: widget.level >= 1000 ? 13 : 16)),
      ),
    );
    if (_c != null) {
      node = ScaleTransition(
          scale: Tween(begin: 1.0, end: 1.08).animate(CurvedAnimation(parent: _c!, curve: Curves.easeInOut)), child: node);
    }
    if (widget.celebrate) {
      node = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.elasticOut,
        builder: (_, v, child) => Transform.scale(scale: 0.4 + 0.6 * v, child: child),
        child: node,
      );
    }
    return Semantics(
      button: widget.onTap != null,
      label: 'Level ${widget.level}${st == _NodeState.locked ? ', locked' : ''}',
      child: Pressable(
        onTap: widget.onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          node,
          if (st == _NodeState.done) StarRow(stars: widget.stars, size: 12, spacing: 0),
        ]),
      ),
    );
  }
}

/// Pre-level sheet: missions, new mechanics, optional rewarded shield.
class _LevelSheet extends StatelessWidget {
  const _LevelSheet({required this.level, required this.onPlay});
  final int level;
  final void Function(bool withShield) onPlay;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final loaded = LevelGenerator.load(level);
    final c = loaded.config;
    final fresh = LevelGenerator.newMechanicsAt(level);
    final world = WorldTheme.byId(c.worldId);
    final best = s.progress.data.bestScoreFor(level);
    final missions = c.objectives.where((o) => o.type != ObjectiveType.reachFinish);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(22, 14, 22, 22 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.strokeStrong, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Row(children: [
          Text(world.name.toUpperCase(), style: AppText.label.copyWith(color: world.accent)),
          const Spacer(),
          if (c.isChallengeLevel) ...[
            const TierBadge(label: 'Challenge', color: AppColors.star, small: true),
            const SizedBox(width: 6),
          ],
          TierBadge(label: c.tier.label, color: Color(c.tier.argb), small: true),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Text('Level $level', style: AppText.title),
          const Spacer(),
          StarRow(stars: s.progress.data.starsFor(level), size: 20),
        ]),
        if (best > 0) Text('Best score $best', style: AppText.bodyDim),
        const SizedBox(height: 14),
        for (final m in missions) _line(Icons.flag_rounded, 'Mission · ${m.describe()}', AppColors.star),
        _line(Icons.star_rounded, c.starObjectives.isNotEmpty ? '★★ ${c.starObjectives[0].describe()}' : 'Reach the finish',
            AppColors.textDim),
        if (c.starObjectives.length > 1) _line(Icons.star_rounded, '★★★ ${c.starObjectives[1].describe()}', AppColors.textDim),
        for (final m in fresh) _line(Icons.fiber_new_rounded, m.title, AppColors.brand2),
        if (c.gravityMode != GravityMode.manual)
          _line(Icons.autorenew_rounded, c.gravityMode == GravityMode.rotating ? 'Rotating gravity' : 'Reversing gravity',
              AppColors.brand2),
        const SizedBox(height: 18),
        PrimaryButton(label: 'Play', icon: Icons.play_arrow_rounded, onTap: () => onPlay(false)),
        if (s.monetization.ads.rewardedReady) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              final ok = await s.monetization.rewarded(() {});
              if (ok) onPlay(true);
            },
            icon: const Icon(Icons.shield_rounded, color: Color(0xFF9FD8FF)),
            label: Text('Watch ad · Start with a Shield', style: AppText.body.copyWith(color: const Color(0xFF9FD8FF))),
          ),
        ],
      ]),
    );
  }

  Widget _line(IconData icon, String text, Color color) => FadeSlideIn(
        delay: const Duration(milliseconds: 120),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: AppText.body)),
          ]),
        ),
      );
}
