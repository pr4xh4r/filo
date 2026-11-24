import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/theme/filo_colors.dart';
import '../../../core/theme/filo_typography.dart';

/// Fullscreen camera QR code scanner tailored for Filo cross-device vault pairing.
/// Features hardware-accelerated preview, corner brackets, animated scan line,
/// torch toggle, and fallback for manual entry.
class FiloQrScannerScreen extends StatefulWidget {
  final String title;
  final String hint;

  const FiloQrScannerScreen({
    super.key,
    this.title = 'Scan QR Code',
    this.hint = 'Align the QR code within the frame to pair',
  });

  /// Opens the camera scanner and returns the raw scanned string or null if cancelled.
  static Future<String?> open(
    BuildContext context, {
    String title = 'Scan QR Code',
    String hint = 'Align the QR code within the frame to pair',
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => FiloQrScannerScreen(title: title, hint: hint),
      ),
    );
  }

  @override
  State<FiloQrScannerScreen> createState() => _FiloQrScannerScreenState();
}

class _FiloQrScannerScreenState extends State<FiloQrScannerScreen>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _controller;
  late final AnimationController _animController;
  bool _hasScanned = false;
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.normal,
    );
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _hasScanned = true;
        HapticFeedback.heavyImpact();
        Navigator.of(context).pop(value.trim());
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const double frameSize = 250.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Live Camera Preview
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.no_photography_outlined,
                          color: Colors.white60,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Camera Access Required',
                          style: FiloTypography.title2.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Please grant camera permissions in device settings to scan pairing QR codes.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: FiloTypography.fontFamily,
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // 2. Translucent Cutout Overlay
          const Positioned.fill(
            child: CustomPaint(
              painter: _ScannerOverlayPainter(cutoutSize: frameSize),
            ),
          ),

          // 3. Animated Scanning Line inside Viewfinder
          Center(
            child: SizedBox(
              width: frameSize,
              height: frameSize,
              child: AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  return Stack(
                    children: [
                      Positioned(
                        top: _animController.value * (frameSize - 4),
                        left: 8,
                        right: 8,
                        child: Container(
                          height: 2.5,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                FiloColors.accentCoral.withValues(alpha: 0.1),
                                FiloColors.accentCoral,
                                FiloColors.accentCoral.withValues(alpha: 0.1),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: FiloColors.accentCoral.withValues(alpha: 0.8),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // 4. Viewfinder Frame Corners
          const Center(
            child: SizedBox(
              width: frameSize,
              height: frameSize,
              child: CustomPaint(
                painter: _CornerBracketPainter(),
              ),
            ),
          ),

          // 5. Header Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // Back Button
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: FiloTypography.title2.copyWith(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    // Torch Button
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _isTorchOn
                              ? FiloColors.accentCoral
                              : Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Icon(
                          _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                      onPressed: () async {
                        await _controller.toggleTorch();
                        setState(() => _isTorchOn = !_isTorchOn);
                      },
                    ),
                    // Switch Camera Button
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(
                          Icons.flip_camera_ios_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                      onPressed: () => _controller.switchCamera(),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 6. Bottom Guide & Manual Entry Button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.hint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: FiloTypography.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.9),
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 8),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Fallback to manual paste
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).pop('MANUAL_ENTRY');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: Colors.white30),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.keyboard_alt_outlined, size: 16, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'Enter Token Manually',
                              style: TextStyle(
                                fontFamily: FiloTypography.fontFamily,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Semi-transparent dark overlay with rounded cutout for QR scanner viewfinder
class _ScannerOverlayPainter extends CustomPainter {
  final double cutoutSize;

  const _ScannerOverlayPainter({required this.cutoutSize});

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final cutoutRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: cutoutSize,
      height: cutoutSize,
    );

    final cutoutPath = Path()
      ..addRRect(RRect.fromRectAndRadius(cutoutRect, const Radius.circular(20)));

    final overlayPath = Path.combine(PathOperation.difference, backgroundPath, cutoutPath);

    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.58)
      ..style = PaintingStyle.fill;

    canvas.drawPath(overlayPath, paint);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) =>
      oldDelegate.cutoutSize != cutoutSize;
}

/// Modern corner bracket markers for the QR scanner
class _CornerBracketPainter extends CustomPainter {
  const _CornerBracketPainter();
  @override
  void paint(Canvas canvas, Size size) {
    const double length = 26.0;
    const double strokeWidth = 3.5;
    const double radius = 12.0;

    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    // Top-Left
    final tl = Path()
      ..moveTo(0, length)
      ..lineTo(0, radius)
      ..arcToPoint(const Offset(radius, 0), radius: const Radius.circular(radius))
      ..lineTo(length, 0);
    canvas.drawPath(tl, paint);

    // Top-Right
    final tr = Path()
      ..moveTo(w - length, 0)
      ..lineTo(w - radius, 0)
      ..arcToPoint(Offset(w, radius), radius: const Radius.circular(radius))
      ..lineTo(w, length);
    canvas.drawPath(tr, paint);

    // Bottom-Left
    final bl = Path()
      ..moveTo(0, h - length)
      ..lineTo(0, h - radius)
      ..arcToPoint(Offset(radius, h), radius: const Radius.circular(radius))
      ..lineTo(length, h);
    canvas.drawPath(bl, paint);

    // Bottom-Right
    final br = Path()
      ..moveTo(w - length, h)
      ..lineTo(w - radius, h)
      ..arcToPoint(Offset(w, h - radius), radius: const Radius.circular(radius))
      ..lineTo(w, h - length);
    canvas.drawPath(br, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketPainter oldDelegate) => false;
}
