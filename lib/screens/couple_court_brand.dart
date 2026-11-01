import 'dart:math' as math;

import 'package:flutter/material.dart';

class CoupleCourtBrand extends StatelessWidget {
  const CoupleCourtBrand({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Couple Court',
    child: const ExcludeSemantics(
      child: SizedBox(
        height: 110,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 76,
              height: 76,
              child: CustomPaint(painter: CourtMarkPainter()),
            ),
            SizedBox(width: 14),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Couple Court',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB85842),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Original vector mark, also rendered into the website's install icons.
class CourtMarkPainter extends CustomPainter {
  const CourtMarkPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 128, size.height / 128);
    final peach = Paint()..color = const Color(0xFFFFE2D3);
    final ink = Paint()..color = const Color(0xFFB85842);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 128, 128),
        const Radius.circular(32),
      ),
      peach,
    );
    canvas.save();
    canvas.translate(65, 54);
    canvas.rotate(-math.pi / 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-29, -21, 58, 26),
        const Radius.circular(6),
      ),
      ink,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-6, 3, 12, 48),
        const Radius.circular(5),
      ),
      ink,
    );
    final heart = Path()
      ..moveTo(0, -1)
      ..cubicTo(-22, -12, -10, -24, 0, -14)
      ..cubicTo(10, -24, 22, -12, 0, -1)
      ..close();
    canvas.drawPath(heart, Paint()..color = Colors.white);
    canvas.restore();
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(32, 103, 64, 9),
        const Radius.circular(4),
      ),
      ink,
    );
  }

  @override
  bool shouldRepaint(covariant CourtMarkPainter oldDelegate) => false;
}

