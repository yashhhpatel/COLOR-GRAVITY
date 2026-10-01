import 'package:flutter/material.dart';

/// Background decoration style drawn by the world background painter.
enum WorldPattern { hills, gears, orbits, crystals, magnets, skyline, energy, quantum, voidStars, prism }

/// Visual identity of one of the 10 worlds. Backgrounds are deliberately
/// low-saturation so gameplay colors keep their contrast.
class WorldTheme {
  const WorldTheme({
    required this.id,
    required this.name,
    required this.tagline,
    required this.top,
    required this.bottom,
    required this.accent,
    required this.pattern,
    required this.musicTrack,
  });

  final int id;
  final String name;
  final String tagline;
  final Color top;
  final Color bottom;
  final Color accent;
  final WorldPattern pattern;
  final int musicTrack; // 0..2

  static const List<WorldTheme> all = [
    WorldTheme(
        id: 0,
        name: 'Color Valley',
        tagline: 'Where every fall begins',
        top: Color(0xFF13203F),
        bottom: Color(0xFF0B1226),
        accent: Color(0xFF6FA8FF),
        pattern: WorldPattern.hills,
        musicTrack: 0),
    WorldTheme(
        id: 1,
        name: 'Gravity Factory',
        tagline: 'Gears that bend the pull',
        top: Color(0xFF241A2E),
        bottom: Color(0xFF120D18),
        accent: Color(0xFFFF9F5A),
        pattern: WorldPattern.gears,
        musicTrack: 1),
    WorldTheme(
        id: 2,
        name: 'Neon Orbit',
        tagline: 'Circle the glow',
        top: Color(0xFF1A1440),
        bottom: Color(0xFF0B0A20),
        accent: Color(0xFFB07CFF),
        pattern: WorldPattern.orbits,
        musicTrack: 2),
    WorldTheme(
        id: 3,
        name: 'Crystal Space',
        tagline: 'Sharp light, sharp turns',
        top: Color(0xFF0F2A36),
        bottom: Color(0xFF07141C),
        accent: Color(0xFF6BE3FF),
        pattern: WorldPattern.crystals,
        musicTrack: 0),
    WorldTheme(
        id: 4,
        name: 'Magnetic Lab',
        tagline: 'Opposites pull',
        top: Color(0xFF1E2430),
        bottom: Color(0xFF0D1118),
        accent: Color(0xFF9FB4D8),
        pattern: WorldPattern.magnets,
        musicTrack: 1),
    WorldTheme(
        id: 5,
        name: 'Floating City',
        tagline: 'Skylines upside down',
        top: Color(0xFF2A1F3D),
        bottom: Color(0xFF120E1E),
        accent: Color(0xFFFFB27A),
        pattern: WorldPattern.skyline,
        musicTrack: 2),
    WorldTheme(
        id: 6,
        name: 'Energy Core',
        tagline: 'Ride the current',
        top: Color(0xFF2B1420),
        bottom: Color(0xFF14080F),
        accent: Color(0xFFFF6F91),
        pattern: WorldPattern.energy,
        musicTrack: 1),
    WorldTheme(
        id: 7,
        name: 'Quantum World',
        tagline: 'Every path at once',
        top: Color(0xFF0F2B26),
        bottom: Color(0xFF061512),
        accent: Color(0xFF5CF2C2),
        pattern: WorldPattern.quantum,
        musicTrack: 0),
    WorldTheme(
        id: 8,
        name: 'Gravity Void',
        tagline: 'Nothing holds you here',
        top: Color(0xFF0B0B14),
        bottom: Color(0xFF020205),
        accent: Color(0xFFC9C9FF),
        pattern: WorldPattern.voidStars,
        musicTrack: 2),
    WorldTheme(
        id: 9,
        name: 'Final Color Core',
        tagline: 'Master both',
        top: Color(0xFF221836),
        bottom: Color(0xFF0D0A18),
        accent: Color(0xFFFFE07A),
        pattern: WorldPattern.prism,
        musicTrack: 1),
  ];

  static WorldTheme forLevel(int level) => all[((level - 1) ~/ 100).clamp(0, 9)];
  static WorldTheme byId(int id) => all[id.clamp(0, 9)];
}
