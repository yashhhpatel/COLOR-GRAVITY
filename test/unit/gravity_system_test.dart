import 'package:color_gravity/core/models/gravity_dir.dart';
import 'package:color_gravity/game/entities/entity.dart';
import 'package:color_gravity/game/systems/gravity_system.dart';
import 'package:color_gravity/levels/models/level_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GravityDir', () {
    test('vectors, opposites and clockwise rotation', () {
      expect(GravityDir.down.vector, const Offset(0, 1));
      expect(GravityDir.left.vector, const Offset(-1, 0));
      for (final d in GravityDir.values) {
        expect(d.opposite.opposite, d);
        expect(d.clockwise.clockwise.clockwise.clockwise, d);
      }
    });

    test('swipe vector maps to dominant direction', () {
      expect(GravityDir.fromVector(const Offset(40, 5)), GravityDir.right);
      expect(GravityDir.fromVector(const Offset(-40, 10)), GravityDir.left);
      expect(GravityDir.fromVector(const Offset(3, -50)), GravityDir.up);
      expect(GravityDir.fromVector(const Offset(-3, 50)), GravityDir.down);
    });
  });

  group('GravitySystem', () {
    test('player request changes direction once', () {
      final g = GravitySystem(smooth: false);
      final c = g.request(GravityDir.left, GravitySource.player);
      expect(c, isNotNull);
      expect(c!.from, GravityDir.down);
      expect(g.dir, GravityDir.left);
      expect(g.vector, const Offset(-1, 0));
      expect(g.request(GravityDir.left, GravitySource.player), isNull);
    });

    test('smooth transition blends then settles', () {
      final g = GravitySystem(smooth: true);
      g.request(GravityDir.up, GravitySource.player);
      g.update(0.05);
      expect(g.transitioning, isTrue);
      expect(g.vector.dy, lessThan(1));
      expect(g.vector.dy, greaterThan(-1));
      g.update(0.5);
      expect(g.transitioning, isFalse);
      expect(g.vector, const Offset(0, -1));
    });

    test('all four directions are reachable', () {
      final g = GravitySystem(smooth: false);
      for (final d in [GravityDir.left, GravityDir.up, GravityDir.right, GravityDir.down]) {
        g.request(d, GravitySource.player);
        expect(g.dir, d);
        expect(g.vector, d.vector);
      }
    });

    test('gravity lock zone blocks player shifts unless overridden', () {
      final g = GravitySystem(smooth: false)..zoneLocked = true;
      expect(g.request(GravityDir.left, GravitySource.player), isNull);
      expect(g.request(GravityDir.left, GravitySource.player, override: true), isNotNull);
    });

    test('gravity freeze ignores external changes but not the player', () {
      final g = GravitySystem(smooth: false)..frozen = true;
      expect(g.request(GravityDir.left, GravitySource.switchPad), isNull);
      expect(g.request(GravityDir.left, GravitySource.player), isNotNull);
    });

    test('reversing gravity flips after the interval with a warning first', () {
      final g = GravitySystem(smooth: false, mode: GravityMode.reversing, interval: 2);
      g.update(1.5);
      expect(g.warning, GravityDir.up);
      final c = g.update(0.6);
      expect(c?.to, GravityDir.up);
      expect(g.warning, isNull);
      g.update(2.1);
      expect(g.dir, GravityDir.down);
    });

    test('rotating gravity goes clockwise and blocks swipes', () {
      final g = GravitySystem(smooth: false, mode: GravityMode.rotating, interval: 1);
      expect(g.canPlayerShift(), isFalse);
      final seen = <GravityDir>[];
      for (var i = 0; i < 4; i++) {
        g.update(1.01);
        seen.add(g.dir);
      }
      expect(seen, [GravityDir.left, GravityDir.up, GravityDir.right, GravityDir.down]);
    });

    test('zones force gravity while inside and restore on exit', () {
      final g = GravitySystem(smooth: false);
      final zone = Entity(kind: EntityKind.gravityZone, dir: GravityDir.right);
      g.enterZone(zone);
      expect(g.dir, GravityDir.right);
      expect(g.canPlayerShift(), isFalse);
      g.exitZone();
      expect(g.dir, GravityDir.down);
    });

    test('gravity bomb reverses temporarily', () {
      final g = GravitySystem(smooth: false);
      g.temporaryReverse(1);
      expect(g.dir, GravityDir.up);
      g.update(1.1);
      expect(g.dir, GravityDir.down);
    });
  });
}
