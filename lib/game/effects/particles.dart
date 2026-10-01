import 'dart:math' as math;
import 'dart:ui';

enum ParticleStyle { dot, spark, ring, shard }

/// Fixed-size particle pool (no per-frame allocation once warm).
class ParticlePool {
  ParticlePool({this.capacity = 280}) {
    for (var i = 0; i < capacity; i++) {
      _all.add(Particle());
    }
  }

  final int capacity;
  final List<Particle> _all = [];
  final math.Random _rng = math.Random();
  int _cursor = 0;

  Iterable<Particle> get active => _all.where((p) => p.life > 0);

  Particle _next() {
    // Reuse a dead particle, or overwrite the oldest slot.
    for (var i = 0; i < capacity; i++) {
      final p = _all[(_cursor + i) % capacity];
      if (p.life <= 0) {
        _cursor = (_cursor + i + 1) % capacity;
        return p;
      }
    }
    _cursor = (_cursor + 1) % capacity;
    return _all[_cursor];
  }

  void emit({
    required double x,
    required double y,
    required Color color,
    int count = 12,
    double speed = 160,
    double spread = math.pi * 2,
    double direction = 0,
    double life = 0.6,
    double size = 3,
    ParticleStyle style = ParticleStyle.dot,
    double gravityScale = 0,
    Offset gravity = Offset.zero,
  }) {
    for (var i = 0; i < count; i++) {
      final p = _next();
      final a = direction + (_rng.nextDouble() - 0.5) * spread;
      final s = speed * (0.45 + _rng.nextDouble() * 0.75);
      p
        ..x = x
        ..y = y
        ..vx = math.cos(a) * s
        ..vy = math.sin(a) * s
        ..maxLife = life * (0.7 + _rng.nextDouble() * 0.5)
        ..life = p.maxLife
        ..size = size * (0.6 + _rng.nextDouble() * 0.8)
        ..color = color
        ..style = style
        ..gx = gravity.dx * gravityScale
        ..gy = gravity.dy * gravityScale
        ..rot = _rng.nextDouble() * math.pi;
    }
  }

  void ring({required double x, required double y, required Color color, double size = 30, double life = 0.45}) {
    final p = _next();
    p
      ..x = x
      ..y = y
      ..vx = 0
      ..vy = 0
      ..maxLife = life
      ..life = life
      ..size = size
      ..color = color
      ..style = ParticleStyle.ring
      ..gx = 0
      ..gy = 0;
  }

  void update(double dt, double scroll) {
    for (final p in _all) {
      if (p.life <= 0) continue;
      p.life -= dt;
      p.vx += p.gx * dt;
      p.vy += p.gy * dt;
      p.vx *= 1 - 1.8 * dt;
      p.vy *= 1 - 1.8 * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt + scroll * 0.6;
      p.rot += dt * 4;
    }
  }

  void clear() {
    for (final p in _all) {
      p.life = 0;
    }
  }
}

class Particle {
  double x = 0, y = 0, vx = 0, vy = 0, gx = 0, gy = 0;
  double life = 0, maxLife = 1, size = 3, rot = 0;
  Color color = const Color(0xFFFFFFFF);
  ParticleStyle style = ParticleStyle.dot;
  double get t => (life / maxLife).clamp(0.0, 1.0);
}

/// Floating score / feedback text.
class FloatingText {
  FloatingText(this.text, this.x, this.y, this.color, {this.big = false}) : life = big ? 1.2 : 0.9;
  final String text;
  double x, y;
  final Color color;
  final bool big;
  double life;
  double get maxLife => big ? 1.2 : 0.9;
}

/// Subtle camera: shake on hits, zoom pulse on big merges and gravity shifts.
class GameCamera {
  double _shake = 0;
  double _zoom = 0;
  double _time = 0;
  final math.Random _rng = math.Random();

  void shake(double amount) => _shake = math.max(_shake, amount);
  void pulse(double amount) => _zoom = math.max(_zoom, amount);

  void update(double dt) {
    _time += dt;
    _shake = math.max(0, _shake - dt * 18);
    _zoom = math.max(0, _zoom - dt * 0.15);
  }

  Offset get offset => _shake <= 0 ? Offset.zero : Offset((_rng.nextDouble() - 0.5) * _shake, (_rng.nextDouble() - 0.5) * _shake);

  double get zoom => 1 + _zoom;

  double get time => _time;
}
