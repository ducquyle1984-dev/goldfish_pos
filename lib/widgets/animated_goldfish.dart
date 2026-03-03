import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A small animated goldfish that swims in the app bar.
class AnimatedGoldfish extends StatefulWidget {
  /// Total width of the widget (fish + text area).
  final double size;

  const AnimatedGoldfish({super.key, this.size = 40});

  @override
  State<AnimatedGoldfish> createState() => _AnimatedGoldfishState();
}

class _AnimatedGoldfishState extends State<AnimatedGoldfish>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(painter: _GoldfishPainter(_ctrl.value)),
      ),
    );
  }
}

class _GoldfishPainter extends CustomPainter {
  final double t; // 0.0 → 1.0 animation progress

  _GoldfishPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Swim cycle: tail swings ±1, body tilts slightly
    final swing = math.sin(t * 2 * math.pi); // −1 … +1
    final bodyTilt = swing * 0.08; // radians

    // Centre the fish
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(bodyTilt);

    final bodyW = w * 0.50;
    final bodyH = h * 0.28;

    // ── Tail (drawn behind body) ─────────────────────────────────────
    final tailSwing = swing * w * 0.10;
    final tailBase = Offset(-bodyW * 0.85, 0);

    final tailPaint = Paint()
      ..color = const Color(0xFFFF8C00)
      ..style = PaintingStyle.fill;

    final tailPath = Path()
      ..moveTo(tailBase.dx, tailBase.dy)
      ..quadraticBezierTo(
        tailBase.dx - w * 0.18,
        tailBase.dy - h * 0.18 + tailSwing * 0.4,
        tailBase.dx - w * 0.32,
        tailBase.dy - h * 0.28 + tailSwing,
      )
      ..quadraticBezierTo(
        tailBase.dx - w * 0.22,
        tailBase.dy,
        tailBase.dx - w * 0.32,
        tailBase.dy + h * 0.28 - tailSwing,
      )
      ..quadraticBezierTo(
        tailBase.dx - w * 0.18,
        tailBase.dy + h * 0.18 - tailSwing * 0.4,
        tailBase.dx,
        tailBase.dy,
      )
      ..close();
    canvas.drawPath(tailPath, tailPaint);

    // ── Body ─────────────────────────────────────────────────────────
    final bodyGradient = RadialGradient(
      center: const Alignment(0.2, -0.3),
      radius: 0.9,
      colors: [
        const Color(0xFFFFD700), // golden yellow highlight
        const Color(0xFFFF8C00), // deep orange
        const Color(0xFFCC4400), // dark edge
      ],
      stops: const [0.0, 0.55, 1.0],
    );

    final bodyRect = Rect.fromCenter(
      center: Offset(bodyW * 0.06, 0),
      width: bodyW * 2,
      height: bodyH * 2,
    );

    final bodyPaint = Paint()
      ..shader = bodyGradient.createShader(bodyRect)
      ..style = PaintingStyle.fill;

    canvas.drawOval(bodyRect, bodyPaint);

    // ── Dorsal fin ───────────────────────────────────────────────────
    final dorsalSwing = swing * w * 0.04;
    final dorsalPaint = Paint()
      ..color = const Color(0xFFFF6600).withOpacity(0.85)
      ..style = PaintingStyle.fill;

    final dorsalPath = Path()
      ..moveTo(-bodyW * 0.1, -bodyH)
      ..quadraticBezierTo(
        -bodyW * 0.0 + dorsalSwing,
        -bodyH * 2.4,
        bodyW * 0.35,
        -bodyH * 1.05,
      )
      ..quadraticBezierTo(bodyW * 0.1, -bodyH * 0.9, -bodyW * 0.1, -bodyH)
      ..close();
    canvas.drawPath(dorsalPath, dorsalPaint);

    // ── Pectoral fin ─────────────────────────────────────────────────
    final pectSwing = swing * w * 0.03;
    final pectPaint = Paint()
      ..color = const Color(0xFFFF7700).withOpacity(0.75)
      ..style = PaintingStyle.fill;

    final pectPath = Path()
      ..moveTo(bodyW * 0.1, bodyH * 0.3)
      ..quadraticBezierTo(
        bodyW * 0.25 + pectSwing,
        bodyH * 1.5,
        -bodyW * 0.15 + pectSwing,
        bodyH * 1.15,
      )
      ..quadraticBezierTo(-bodyW * 0.05, bodyH * 0.8, bodyW * 0.1, bodyH * 0.3)
      ..close();
    canvas.drawPath(pectPath, pectPaint);

    // ── Scales (subtle arcs) ─────────────────────────────────────────
    final scalePaint = Paint()
      ..color = const Color(0xFFFFAA00).withOpacity(0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    for (final cx in [-0.05, 0.20, 0.42]) {
      for (final cy in [-0.4, 0.1, 0.55]) {
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(cx * bodyW * 2, cy * bodyH * 2),
            width: bodyW * 0.55,
            height: bodyH * 0.9,
          ),
          math.pi * 0.7,
          math.pi * 0.7,
          false,
          scalePaint,
        );
      }
    }

    // ── Eye ──────────────────────────────────────────────────────────
    final eyeX = bodyW * 0.58;
    final eyeY = -bodyH * 0.22;
    final eyeR = w * 0.055;

    canvas.drawCircle(Offset(eyeX, eyeY), eyeR, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(eyeX + eyeR * 0.15, eyeY + eyeR * 0.1),
      eyeR * 0.55,
      Paint()..color = const Color(0xFF1A1A1A),
    );
    // Eye shine
    canvas.drawCircle(
      Offset(eyeX + eyeR * 0.05, eyeY - eyeR * 0.25),
      eyeR * 0.22,
      Paint()..color = Colors.white.withOpacity(0.9),
    );

    // ── Mouth ────────────────────────────────────────────────────────
    final mouthPaint = Paint()
      ..color = const Color(0xFFCC3300)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(bodyW * 0.88, bodyH * 0.15),
        width: w * 0.09,
        height: h * 0.07,
      ),
      math.pi * 0.1,
      math.pi * 0.8,
      false,
      mouthPaint,
    );

    // ── Bubble (appears rhythmically) ─────────────────────────────────
    // bubble rises once per cycle, fading in, floating up, fading out
    final bubblePhase = (t * 1.0) % 1.0;
    if (bubblePhase < 0.55) {
      final bubbleProgress = bubblePhase / 0.55;
      final bubbleOpacity = (math.sin(
        bubbleProgress * math.pi,
      )).clamp(0.0, 1.0);
      final bubbleY = -bodyH * 0.8 - bubbleProgress * h * 0.30;
      canvas.drawCircle(
        Offset(bodyW * 0.80, bubbleY),
        w * 0.038,
        Paint()
          ..color = Colors.lightBlueAccent.withOpacity(bubbleOpacity * 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoldfishPainter old) => old.t != t;
}
