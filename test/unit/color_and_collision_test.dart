import 'dart:ui';

import 'package:color_gravity/core/models/game_color.dart';
import 'package:color_gravity/core/models/gravity_dir.dart';
import 'package:color_gravity/game/collision/collision.dart';
import 'package:color_gravity/game/entities/entity.dart';
import 'package:color_gravity/game/systems/color_system.dart';
import 'package:flutter_test/flutter_test.dart';

Entity orb(GameColor? c, {int level = 1, bool wild = false}) =>
    Entity(kind: EntityKind.orb, color: c, level: level, wildcard: wild, r: Entity.orbRadius(level));

void main() {
  const cs = ColorSystem();

  group('ColorSystem', () {
    test('collect only matching colors or wildcards', () {
      expect(cs.canCollect(GameColor.red, orb(GameColor.red)), isTrue);
      expect(cs.canCollect(GameColor.red, orb(GameColor.blue)), isFalse);
      expect(cs.canCollect(GameColor.blue, orb(null, wild: true)), isTrue);
    });

    test('merge needs same color and level', () {
      expect(cs.canMerge(orb(GameColor.red), orb(GameColor.red)), isTrue);
      expect(cs.canMerge(orb(GameColor.red), orb(GameColor.blue)), isFalse);
      expect(cs.canMerge(orb(GameColor.red, level: 2), orb(GameColor.red)), isFalse);
      expect(cs.canMerge(orb(GameColor.red, level: 2), orb(GameColor.red), mega: true), isTrue);
      expect(cs.canMerge(orb(null, wild: true), orb(GameColor.green)), isTrue);
      expect(cs.canMerge(orb(GameColor.red, level: 6), orb(GameColor.red, level: 6)), isFalse);
      expect(cs.mergedColor(orb(null, wild: true), orb(GameColor.green)), GameColor.green);
    });

    test('gates check color, mode and gravity', () {
      final redGate = Entity(kind: EntityKind.gate, gateColors: [GameColor.red]);
      expect(cs.gateCheck(redGate, GameColor.red, GravityDir.down), GateResult.pass);
      expect(cs.gateCheck(redGate, GameColor.blue, GravityDir.down), GateResult.wrongColor);
      expect(cs.gateCheck(redGate, GameColor.blue, GravityDir.down, colorFrozen: true), GateResult.pass);

      final blueBarrier = Entity(kind: EntityKind.gate, gateColors: [GameColor.blue], gateMode: GateMode.block);
      expect(cs.gateCheck(blueBarrier, GameColor.blue, GravityDir.down), GateResult.wrongColor);
      expect(cs.gateCheck(blueBarrier, GameColor.red, GravityDir.down), GateResult.pass);

      final redUp = Entity(kind: EntityKind.gate, gateColors: [GameColor.red], gateDir: GravityDir.up);
      expect(cs.gateCheck(redUp, GameColor.red, GravityDir.down), GateResult.wrongGravity);
      expect(cs.gateCheck(redUp, GameColor.red, GravityDir.up), GateResult.pass);

      final multi = Entity(kind: EntityKind.gate, gateColors: [GameColor.red, GameColor.green]);
      expect(cs.gateCheck(multi, GameColor.green, GravityDir.left), GateResult.pass);
    });

    test('colored hazards only hurt their color', () {
      final neutral = Entity(kind: EntityKind.spikes);
      final redSpikes = Entity(kind: EntityKind.spikes, dangerColor: GameColor.red);
      expect(cs.isDangerous(neutral, GameColor.blue), isTrue);
      expect(cs.isDangerous(redSpikes, GameColor.red), isTrue);
      expect(cs.isDangerous(redSpikes, GameColor.blue), isFalse);
      expect(cs.isDangerous(redSpikes, GameColor.red, colorFrozen: true), isFalse);
    });

    test('gates filter loose orbs by color', () {
      final redGate = Entity(kind: EntityKind.gate, gateColors: [GameColor.red]);
      expect(cs.orbPassesGate(redGate, orb(GameColor.red)), isTrue);
      expect(cs.orbPassesGate(redGate, orb(GameColor.blue)), isFalse);
      expect(cs.orbPassesGate(Entity(kind: EntityKind.gate, gateDir: GravityDir.up), orb(GameColor.blue)), isTrue);
    });

    test('every color has a unique accessibility shape', () {
      final shapes = GameColor.values.map((c) => c.shape).toSet();
      expect(shapes.length, GameColor.values.length);
    });
  });

  group('Collision', () {
    test('circle vs rect', () {
      const r = Rect.fromLTWH(0, 0, 10, 10);
      expect(Collision.circleRect(15, 5, 6, r), isTrue);
      expect(Collision.circleRect(17, 5, 6, r), isFalse);
      expect(Collision.circleCircle(0, 0, 5, 9, 0, 5), isTrue);
      expect(Collision.circleCircle(0, 0, 5, 11, 0, 5), isFalse);
    });

    test('segment distance', () {
      expect(Collision.segmentDistance(const Offset(5, 3), Offset.zero, const Offset(10, 0)), closeTo(3, 1e-9));
      expect(Collision.segmentDistance(const Offset(-4, 3), Offset.zero, const Offset(10, 0)), closeTo(5, 1e-9));
    });

    test('rotor and laser hazards', () {
      final rotor = Entity(kind: EntityKind.rotor, x: 100, y: 100, w: 100, h: 12, angle: 0);
      expect(Collision.hazardDistance(rotor, 140, 100, GravityDir.down), lessThan(0));
      expect(Collision.hazardDistance(rotor, 100, 140, GravityDir.down), greaterThan(20));

      final laser = Entity(kind: EntityKind.laser, x: 180, y: 300, w: 344, h: 8, period: 2, duty: 0.5);
      laser.age = 0.1; // on
      expect(Collision.hazardDistance(laser, 180, 300, GravityDir.down), lessThanOrEqualTo(0));
      laser.age = 1.5; // off
      expect(Collision.hazardDistance(laser, 180, 300, GravityDir.down), greaterThan(100));
    });

    test('gravity laser follows gravity', () {
      final l = Entity(kind: EntityKind.laser, x: 90, y: 300, w: 16, h: 16, followsGravity: true);
      expect(Collision.hazardDistance(l, 90, 500, GravityDir.down), lessThan(0));
      expect(Collision.hazardDistance(l, 90, 500, GravityDir.up), greaterThan(100));
      expect(Collision.hazardDistance(l, 300, 300, GravityDir.right), lessThan(0));
    });
  });
}
