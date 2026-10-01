import 'package:flutter/material.dart';

enum CosmeticCategory {
  skin('Skins'),
  trail('Trails'),
  gravityFx('Gravity FX'),
  mergeFx('Merge FX');

  const CosmeticCategory(this.title);
  final String title;
}

/// A purely visual unlockable. Nothing here changes gameplay.
class Cosmetic {
  const Cosmetic(this.id, this.category, this.name, this.price, this.preview, {this.description = ''});
  final String id;
  final CosmeticCategory category;
  final String name;
  final int price; // coins; 0 = free default
  final Color preview;
  final String description;
}

class Cosmetics {
  // Skins
  static const classic =
      Cosmetic('skin_classic', CosmeticCategory.skin, 'Classic', 0, Color(0xFFFFFFFF), description: 'Clean glowing core');
  static const crystal =
      Cosmetic('skin_crystal', CosmeticCategory.skin, 'Crystal', 300, Color(0xFFBFF4FF), description: 'Faceted glass');
  static const neon =
      Cosmetic('skin_neon', CosmeticCategory.skin, 'Neon', 500, Color(0xFF8CFFE8), description: 'Hollow light ring');
  static const shadow =
      Cosmetic('skin_shadow', CosmeticCategory.skin, 'Shadow', 700, Color(0xFF3A3F5C), description: 'Dark core, bright rim');
  static const gold =
      Cosmetic('skin_gold', CosmeticCategory.skin, 'Gold', 1200, Color(0xFFFFD45C), description: 'Polished gold rim');
  static const galaxy =
      Cosmetic('skin_galaxy', CosmeticCategory.skin, 'Galaxy', 1600, Color(0xFF9C7BFF), description: 'A pocket of stars');
  static const cyber =
      Cosmetic('skin_cyber', CosmeticCategory.skin, 'Cyber', 2000, Color(0xFF4DFFB8), description: 'Grid-lined circuit core');

  // Trails
  static const trailLight = Cosmetic('trail_light', CosmeticCategory.trail, 'Light', 0, Color(0xFFFFFFFF));
  static const trailSpark = Cosmetic('trail_spark', CosmeticCategory.trail, 'Spark', 400, Color(0xFFFFE08A));
  static const trailPulse = Cosmetic('trail_pulse', CosmeticCategory.trail, 'Pulse', 700, Color(0xFF8AB6FF));
  static const trailRainbow = Cosmetic('trail_rainbow', CosmeticCategory.trail, 'Rainbow', 1500, Color(0xFFFF8AD8));

  // Gravity effects
  static const gfxEnergy = Cosmetic('gfx_energy', CosmeticCategory.gravityFx, 'Energy', 0, Color(0xFF8FD3FF));
  static const gfxParticle = Cosmetic('gfx_particle', CosmeticCategory.gravityFx, 'Particle', 450, Color(0xFFFFFFFF));
  static const gfxLightning = Cosmetic('gfx_lightning', CosmeticCategory.gravityFx, 'Lightning', 900, Color(0xFFFFF27A));
  static const gfxSpiral = Cosmetic('gfx_spiral', CosmeticCategory.gravityFx, 'Spiral', 1300, Color(0xFFC59BFF));

  // Merge effects
  static const mfxBurst = Cosmetic('mfx_burst', CosmeticCategory.mergeFx, 'Burst', 0, Color(0xFFFFFFFF));
  static const mfxRing = Cosmetic('mfx_ring', CosmeticCategory.mergeFx, 'Ring', 400, Color(0xFF9CE8FF));
  static const mfxCrystal = Cosmetic('mfx_crystal', CosmeticCategory.mergeFx, 'Crystal', 800, Color(0xFFBFF4FF));
  static const mfxEnergy = Cosmetic('mfx_energy', CosmeticCategory.mergeFx, 'Energy', 1200, Color(0xFFFF9BD2));

  static const List<Cosmetic> all = [
    classic,
    crystal,
    neon,
    shadow,
    gold,
    galaxy,
    cyber,
    trailLight,
    trailSpark,
    trailPulse,
    trailRainbow,
    gfxEnergy,
    gfxParticle,
    gfxLightning,
    gfxSpiral,
    mfxBurst,
    mfxRing,
    mfxCrystal,
    mfxEnergy,
  ];

  static List<Cosmetic> of(CosmeticCategory c) => all.where((x) => x.category == c).toList();

  static Cosmetic byId(String? id, CosmeticCategory fallbackCategory) =>
      all.firstWhere((c) => c.id == id, orElse: () => of(fallbackCategory).first);

  static Set<String> get defaults => all.where((c) => c.price == 0).map((c) => c.id).toSet();
}

/// The equipped set, handed to the renderer.
class Loadout {
  const Loadout({
    this.skin = 'skin_classic',
    this.trail = 'trail_light',
    this.gravityFx = 'gfx_energy',
    this.mergeFx = 'mfx_burst',
  });
  final String skin;
  final String trail;
  final String gravityFx;
  final String mergeFx;
}
