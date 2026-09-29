import 'package:flutter/material.dart';

import '../themes/app_colors.dart';

/// The Assessly logo: a teal tile with a filled answer bubble and a tick.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.10)
            : AppColors.primary,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: onDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.18))
            : null,
      ),
      child: Icon(
        Icons.task_alt_rounded,
        color: onDark ? AppColors.primarySoft : Colors.white,
        size: size * 0.55,
      ),
    );
  }
}

/// Logo + wordmark in a row.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.onDark = false, this.size = 40});

  final bool onDark;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: size, onDark: onDark),
        SizedBox(width: size * 0.28),
        Text(
          'Assessly',
          style: TextStyle(
            color: onDark ? Colors.white : AppColors.textPrimary,
            fontSize: size * 0.55,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
      ],
    );
  }
}

/// Flat drawing of an answer sheet: timing marks down the side, rows of
/// bubbles with a few filled in teal. Used on the splash and onboarding.
class SheetIllustration extends StatelessWidget {
  const SheetIllustration({super.key, this.width = 220, this.tilt = -0.06});

  final double width;
  final double tilt;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tilt,
      child: SizedBox(
        width: width,
        height: width * 1.3,
        child: CustomPaint(painter: _SheetPainter()),
      ),
    );
  }
}

class _SheetPainter extends CustomPainter {
  // Which option (0-3) is filled on each row; -1 = left blank.
  static const _answers = [1, 3, 0, 2, 2, -1, 1, 0, 3, 1];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = Radius.circular(w * 0.05);

    // Shadow sheet behind, then the page.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.06, h * 0.04, w * 0.94, h * 0.96),
        r,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.10),
    );
    final page = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w * 0.94, h * 0.96),
      r,
    );
    canvas.drawRRect(page, Paint()..color = const Color(0xFFF8FAFC));

    final ink = Paint()..color = AppColors.ink;
    final line = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.008;
    final fill = Paint()..color = AppColors.primary;

    // Corner markers.
    final m = w * 0.055;
    for (final o in [
      Offset(w * 0.05, h * 0.035),
      Offset(w * 0.94 - w * 0.05 - m, h * 0.035),
      Offset(w * 0.05, h * 0.96 - h * 0.035 - m),
      Offset(w * 0.94 - w * 0.05 - m, h * 0.96 - h * 0.035 - m),
    ]) {
      canvas.drawRect(o & Size(m, m), ink);
    }

    // Title lines.
    final text = Paint()..color = const Color(0xFFE2E8F0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.18, h * 0.07, w * 0.42, h * 0.025),
        const Radius.circular(4),
      ),
      Paint()..color = AppColors.inkSoft,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.18, h * 0.115, w * 0.28, h * 0.018),
        const Radius.circular(4),
      ),
      text,
    );

    // Bubble rows with timing marks on the left.
    final top = h * 0.2;
    final pitch = (h * 0.7) / _answers.length;
    final bubble = w * 0.036;
    for (var row = 0; row < _answers.length; row++) {
      final y = top + row * pitch + pitch / 2;
      canvas.drawRect(
        Rect.fromLTWH(w * 0.07, y - pitch * 0.12, w * 0.035, pitch * 0.24),
        ink,
      );
      for (var col = 0; col < 4; col++) {
        final c = Offset(w * 0.3 + col * w * 0.13, y);
        if (_answers[row] == col) {
          canvas.drawCircle(c, bubble, fill);
        } else {
          canvas.drawCircle(c, bubble, line);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Deep slate background with a soft teal glow in one corner.
class InkBackdrop extends StatelessWidget {
  const InkBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.9, -0.9),
          radius: 1.3,
          colors: [AppColors.primaryDark, AppColors.ink],
        ),
      ),
      child: child,
    );
  }
}
