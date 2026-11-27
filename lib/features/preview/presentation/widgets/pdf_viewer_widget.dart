import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_glass.dart';

/// Lightweight, native hardware-accelerated PDF viewer with smooth page swiping,
/// interactive pinch zoom, direct page jumping, and orientation modes.
class PdfViewerWidget extends StatefulWidget {
  final Uint8List? bytes;
  final File? file;
  final String fileName;

  const PdfViewerWidget({
    super.key,
    this.bytes,
    this.file,
    required this.fileName,
  }) : assert(bytes != null || file != null, 'Either bytes or file must be provided');

  @override
  State<PdfViewerWidget> createState() => _PdfViewerWidgetState();
}

class _PdfViewerWidgetState extends State<PdfViewerWidget> {
  PdfControllerPinch? _pdfController;
  int _actualPageNumber = 1;
  int _allPagesCount = 0;
  bool _isReady = false;
  bool _isVertical = false; // Horizontal page flip by default for natural book-like swiping
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPdf(initialPage: 1);
  }

  Future<void> _initPdf({int initialPage = 1}) async {
    try {
      final oldController = _pdfController;
      if (widget.file != null && await widget.file!.exists()) {
        _pdfController = PdfControllerPinch(
          document: PdfDocument.openFile(widget.file!.path),
          initialPage: initialPage,
        );
      } else if (widget.bytes != null) {
        _pdfController = PdfControllerPinch(
          document: PdfDocument.openData(widget.bytes!),
          initialPage: initialPage,
        );
      } else {
        throw Exception('No PDF data provided');
      }
      if (oldController != null) {
        oldController.dispose();
      }
      if (mounted) {
        setState(() => _isReady = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to load PDF: $e');
      }
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    if (_pdfController == null || page < 1 || page > _allPagesCount) return;
    HapticFeedback.selectionClick();
    _pdfController!.animateToPage(
      pageNumber: page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.picture_as_pdf_outlined,
                size: 48,
                color: FiloColors.destructive,
              ),
              const SizedBox(height: 12),
              Text(
                'Unable to render PDF',
                style: FiloTypography.title3,
              ),
              const SizedBox(height: 4),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12,
                  color: FiloColors.lightTextTertiary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (!_isReady || _pdfController == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(FiloColors.primary),
        ),
      );
    }

    return Stack(
      children: [
        // Native pinch-zoom & smooth page swipe view
        PdfViewPinch(
          key: ValueKey('pdf_view_${_isVertical ? 'v' : 'h'}'),
          controller: _pdfController!,
          scrollDirection: _isVertical ? Axis.vertical : Axis.horizontal,
          padding: 10,
          minScale: 1.0,
          maxScale: 4.0,
          onDocumentLoaded: (doc) {
            if (mounted) {
              setState(() {
                _allPagesCount = doc.pagesCount;
              });
            }
          },
          onPageChanged: (page) {
            if (mounted) {
              setState(() {
                _actualPageNumber = page;
              });
            }
          },
          builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
            options: const DefaultBuilderOptions(),
            documentLoaderBuilder: (_) => const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(FiloColors.primary),
              ),
            ),
            pageLoaderBuilder: (_) => const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(FiloColors.primary),
              ),
            ),
          ),
        ),

        // Floating Liquid Glass Page Navigation Bar
        if (_allPagesCount > 0)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: FiloGlass(
                borderRadius: BorderRadius.circular(100),
                blur: 24.0,
                color: Colors.black.withValues(alpha: 0.78),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Previous Page Button
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 22),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      onPressed: _actualPageNumber > 1
                          ? () => _goToPage(_actualPageNumber - 1)
                          : null,
                    ),
                    const SizedBox(width: 8),

                    // Page Counter indicator
                    Text(
                      '$_actualPageNumber / $_allPagesCount',
                      style: const TextStyle(
                        fontFamily: FiloTypography.fontFamily,
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Next Page Button
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      onPressed: _actualPageNumber < _allPagesCount
                          ? () => _goToPage(_actualPageNumber + 1)
                          : null,
                    ),
                    const SizedBox(width: 10),

                    Container(
                      width: 1,
                      height: 16,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                    const SizedBox(width: 6),

                    // Orientation Switcher (Horizontal Swipe vs Vertical Scroll)
                    IconButton(
                      tooltip: _isVertical ? 'Switch to Horizontal Flip' : 'Switch to Vertical Scroll',
                      icon: Icon(
                        _isVertical ? Icons.swap_horiz_rounded : Icons.swap_vert_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _isVertical = !_isVertical;
                          _initPdf(initialPage: _actualPageNumber);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
