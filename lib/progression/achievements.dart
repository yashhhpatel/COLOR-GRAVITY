import 'package:flutter/material.dart';

import 'save_data.dart';

/// Lifetime stat keys tracked in [SaveData.totals].
class StatKeys {
  static const shifts = 'shifts';
  static const matches = 'matches';
  static const merges = 'merges';
  static const perfect = 'perfect';
  static const perfectRuns = 'perfectRuns';
  static const bestCombo = 'bestCombo';
  static const maxMergeLevel = 'maxMergeLevel';
  static const coinsEarned = 'coinsEarned';
  static const runs = 'runs';
  static const gates = 'gates';
}

class Achievement {
  const Achievement(this.id, this.title, this.description, this.icon, this.target, this.reward, this.metric);
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final int target;
  final int reward;
  final int Function(SaveData d) metric;

  int progress(SaveData d) => metric(d).clamp(0, target);
  bool done(SaveData d) => metric(d) >= target;
}

class Achievements {
  static final List<Achievement> all = [
    Achievement('first_shift', 'First Gravity Shift', 'Shift gravity once', Icons.swap_vert_rounded, 1, 20,
        (d) => d.total(StatKeys.shifts)),
    Achievement('first_match', 'First Color Match', 'Collect an orb of your color', Icons.circle_outlined, 1, 20,
        (d) => d.total(StatKeys.matches)),
    Achievement(
        'first_merge', 'First Merge', 'Combine two orbs', Icons.merge_type_rounded, 1, 20, (d) => d.total(StatKeys.merges)),
    Achievement('perfect_10', '10 Perfect Actions', 'Perfect matches, gates, dodges or shifts', Icons.auto_awesome_rounded, 10,
        50, (d) => d.total(StatKeys.perfect)),
    Achievement('perfect_run', 'Perfect Run', 'Finish a level without a hit', Icons.verified_rounded, 1, 60,
        (d) => d.total(StatKeys.perfectRuns)),
    Achievement('merge_5', 'Big Bang', 'Grow an orb to level 5', Icons.bubble_chart_rounded, 5, 100,
        (d) => d.total(StatKeys.maxMergeLevel)),
    Achievement(
        'combo_master', 'Combo Master', 'Reach a x20 combo', Icons.bolt_rounded, 20, 150, (d) => d.total(StatKeys.bestCombo)),
    Achievement('gravity_master', 'Gravity Master', 'Shift gravity 500 times', Icons.explore_rounded, 500, 150,
        (d) => d.total(StatKeys.shifts)),
    Achievement('color_master', 'Color Master', 'Make 1000 color matches', Icons.palette_rounded, 1000, 150,
        (d) => d.total(StatKeys.matches)),
    Achievement('levels_10', 'Getting a Grip', 'Complete 10 levels', Icons.flag_rounded, 10, 50, (d) => d.levelsCompleted),
    Achievement(
        'levels_100', '100 Levels', 'Complete 100 levels', Icons.emoji_events_rounded, 100, 300, (d) => d.levelsCompleted),
    Achievement('levels_1000', '1000 Levels', 'Complete every level', Icons.workspace_premium_rounded, 1000, 2000,
        (d) => d.levelsCompleted),
    Achievement('stars_150', 'Star Collector', 'Earn 150 stars', Icons.star_rounded, 150, 200, (d) => d.totalStars),
    Achievement('endless_survivor', 'Endless Survivor', 'Travel 5000 in Endless', Icons.all_inclusive_rounded, 5000, 200,
        (d) => d.endlessBestDistance),
    Achievement('daily_7', 'Daily Devotee', 'Reach a 7-day daily streak', Icons.local_fire_department_rounded, 7, 200,
        (d) => d.dailyStreak),
    Achievement('rich', 'Coin Hoarder', 'Earn 2000 coins in total', Icons.savings_rounded, 2000, 100,
        (d) => d.total(StatKeys.coinsEarned)),
  ];
}
