import 'package:flutter/material.dart';

/// Renders the geometric diamond lattice mesh pattern
/// seen in high-end luxury editorial interfaces (reference image 0).
class DiamondPatternPainter extends CustomPainter {
  final Color color;
  final double spacing;
  final double diamondSize;
  final double opacity;

  const DiamondPatternPainter({
    this.color = Colors.white,
    this.spacing = 22.0,
    this.diamondSize = 8.0,
    this.opacity = 0.16,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final half = diamondSize / 2;
    final cols = (size.width / spacing).ceil() + 2;
    final rows = (size.height / spacing).ceil() + 2;

    for (int r = -1; r < rows; r++) {
      final y = r * spacing;
      // Stagger every other row for a true diagonal diamond lattice
      final xOffset = (r % 2 == 0) ? 0.0 : spacing / 2;

      for (int c = -1; c < cols; c++) {
        final x = c * spacing + xOffset;

        final path = Path()
          ..moveTo(x, y - half)
          ..lineTo(x + half, y)
          ..lineTo(x, y + half)
          ..lineTo(x - half, y)
          ..close();

        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DiamondPatternPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.spacing != spacing ||
        oldDelegate.diamondSize != diamondSize ||
        oldDelegate.opacity != opacity;
  }
}

/// A convenient widget that overlays the diamond pattern onto any child or container.
class DiamondPatternOverlay extends StatelessWidget {
  final Widget? child;
  final Color color;
  final double spacing;
  final double diamondSize;
  final double opacity;
  final BorderRadius? borderRadius;

  const DiamondPatternOverlay({
    super.key,
    this.child,
    this.color = Colors.white,
    this.spacing = 22.0,
    this.diamondSize = 7.0,
    this.opacity = 0.16,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final painter = RepaintBoundary(
      child: CustomPaint(
        painter: DiamondPatternPainter(
          color: color,
          spacing: spacing,
          diamondSize: diamondSize,
          opacity: opacity,
        ),
        size: Size.infinite,
      ),
    );

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: Stack(
          children: [
            Positioned.fill(child: painter),
            if (child != null) child!,
          ],
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: painter),
        if (child != null) child!,
      ],
    );
  }
}
