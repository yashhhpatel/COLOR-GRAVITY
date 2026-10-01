import '../../core/models/game_color.dart';
import '../../core/models/gravity_dir.dart';
import '../entities/entity.dart';

enum GateResult { pass, wrongColor, wrongGravity }

/// Central color rules. All "what can interact with what" decisions live here.
class ColorSystem {
  const ColorSystem();

  /// Player can collect this orb (same color, or a wildcard/rainbow).
  bool canCollect(GameColor player, Entity orb) => orb.wildcard || orb.color == player;

  /// Two loose orbs combine when colors match (or one is a wildcard) and
  /// their merge levels are equal.
  bool canMerge(Entity a, Entity b, {bool mega = false}) {
    if (a.kind != EntityKind.orb || b.kind != EntityKind.orb) return false;
    if (a.level >= 6 || b.level >= 6) return false;
    final colorOk = a.wildcard || b.wildcard || a.color == b.color;
    final levelOk = mega ? (a.level - b.level).abs() <= 1 : a.level == b.level;
    return colorOk && levelOk;
  }

  /// Merged color: a wildcard adopts the other orb's color.
  GameColor? mergedColor(Entity a, Entity b) => a.wildcard ? b.color : a.color;

  GateResult gateCheck(Entity gate, GameColor player, GravityDir gravity, {bool colorFrozen = false}) {
    final colors = gate.gateColors;
    if (colors != null && !colorFrozen) {
      final inList = colors.contains(player);
      final ok = gate.gateMode == GateMode.allow ? inList : !inList;
      if (!ok) return GateResult.wrongColor;
    }
    if (gate.gateDir != null && gate.gateDir != gravity) return GateResult.wrongGravity;
    return GateResult.pass;
  }

  /// Loose orbs are filtered by gate colors (color filter); gravity
  /// requirements apply only to the player.
  bool orbPassesGate(Entity gate, Entity orb) {
    final colors = gate.gateColors;
    if (colors == null || orb.wildcard) return true;
    final inList = colors.contains(orb.color);
    return gate.gateMode == GateMode.allow ? inList : !inList;
  }

  /// Neutral hazards always hurt; colored hazards only hurt their color.
  bool isDangerous(Entity hazard, GameColor player, {bool colorFrozen = false}) {
    final c = hazard.dangerColor;
    if (c == null) return true;
    if (colorFrozen) return false;
    return c == player;
  }

  /// Orb delivered into a basin of its color.
  bool basinAccepts(Entity basin, Entity orb) => orb.wildcard || basin.color == orb.color;
}
