import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_typography.dart';

/// Lightweight, native hardware-accelerated PDF viewer with smooth continuous
/// vertical scrolling, interactive pinch-to-zoom, and floating page counter.
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
  late PdfControllerPinch _pdfController;
  int _actualPageNumber = 1;
  int _allPagesCount = 0;
  bool _isReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPdf();
  }

  Future<void> _initPdf() async {
    try {
      if (widget.file != null && await widget.file!.exists()) {
        _pdfController = PdfControllerPinch(
          document: PdfDocument.openFile(widget.file!.path),
        );
      } else if (widget.bytes != null) {
        _pdfController = PdfControllerPinch(
          document: PdfDocument.openData(widget.bytes!),
        );
      } else {
        throw Exception('No PDF data provided');
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
    if (_isReady) {
      _pdfController.dispose();
    }
    super.dispose();
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

    if (!_isReady) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(FiloColors.primary),
        ),
      );
    }

    return Stack(
      children: [
        PdfViewPinch(
          controller: _pdfController,
          scrollDirection: Axis.vertical,
          padding: 8,
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
        if (_allPagesCount > 0)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '$_actualPageNumber / $_allPagesCount',
                  style: const TextStyle(
                    fontFamily: FiloTypography.fontFamily,
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
