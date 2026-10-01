import 'dart:ui';

/// Logical arena. Gameplay always simulates in these units and is scaled
/// to fit the device, so every aspect ratio plays identically.
class Arena {
  static const double width = 360;
  static const double height = 640;

  /// Region the player orb is confined to (the "gravity field").
  static const Rect field = Rect.fromLTRB(22, 150, 338, 604);

  /// Loose objects are kept inside these side walls.
  static const double wallLeft = 8;
  static const double wallRight = 352;

  static const double playerRadius = 14;
}

class Physics {
  /// Player acceleration under gravity (units/s²).
  static const double playerGravity = 2600;
  static const double playerMaxFall = 900;

  /// Loose objects feel gravity more gently than the player.
  static const double looseGravity = 520;
  static const double looseMaxSpeed = 260;

  static const double smoothTransition = 0.32; // seconds
  static const double steerSensitivity = 1.25;

  /// Flick classification for gravity swipes.
  static const double swipeMinDistance = 38; // arena units
  static const double swipeMinSpeed = 0.55; // arena units per ms
  static const int swipeMaxMillis = 320;
}

class GameTiming {
  static const double comboWindow = 2.6;
  static const double invulnerable = 1.4;
  static const double perfectShiftWindow = 0.7;
  static const double scriptedWarning = 0.9;
}
