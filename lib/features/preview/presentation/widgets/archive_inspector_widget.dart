import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_typography.dart';

/// In-app inspector for ZIP archives showing internal file structure and sizes.
class ArchiveInspectorWidget extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;

  const ArchiveInspectorWidget({
    super.key,
    required this.bytes,
    required this.fileName,
  });

  @override
  State<ArchiveInspectorWidget> createState() => _ArchiveInspectorWidgetState();
}

class _ArchiveInspectorWidgetState extends State<ArchiveInspectorWidget> {
  Archive? _archive;
  String? _error;
  int _totalUncompressedSize = 0;

  @override
  void initState() {
    super.initState();
    _parseArchive();
  }

  void _parseArchive() {
    try {
      final decoded = ZipDecoder().decodeBytes(widget.bytes);
      int total = 0;
      for (final file in decoded.files) {
        total += file.size;
      }
      setState(() {
        _archive = decoded;
        _totalUncompressedSize = total;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to inspect ZIP archive: $e';
      });
    }
  }

  IconData _getIconForEntry(String name, bool isFile) {
    if (!isFile) return Icons.folder_outlined;
    final lower = name.toLowerCase();
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return Icons.photo_outlined;
    }
    if (lower.endsWith('.mp4') || lower.endsWith('.mov')) {
      return Icons.videocam_outlined;
    }
    if (lower.endsWith('.mp3') || lower.endsWith('.wav')) {
      return Icons.headphones_outlined;
    }
    if (lower.endsWith('.pdf')) {
      return Icons.picture_as_pdf_outlined;
    }
    return Icons.insert_drive_file_outlined;
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
              const Icon(Icons.archive_outlined, size: 48, color: FiloColors.destructive),
              const SizedBox(height: 12),
              Text('Unable to read ZIP', style: FiloTypography.title3),
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(fontSize: 12, color: FiloColors.lightTextTertiary), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (_archive == null) {
      return const Center(
        child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(FiloColors.primary)),
      );
    }

    final files = _archive!.files;

    return Column(
      children: [
        // Summary Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${files.length} items in archive',
                    style: FiloTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Total uncompressed: ${HashUtils.formatBytes(_totalUncompressedSize)}',
                    style: const TextStyle(fontSize: 12, color: FiloColors.lightTextTertiary),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: FiloColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'ZIP ARCHIVE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: FiloColors.primary),
                ),
              ),
            ],
          ),
        ),

        // Files List
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: files.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 54,
              color: Colors.black.withValues(alpha: 0.04),
            ),
            itemBuilder: (context, index) {
              final entry = files[index];
              return ListTile(
                dense: true,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getIconForEntry(entry.name, entry.isFile),
                    size: 18,
                    color: FiloColors.lightTextPrimary,
                  ),
                ),
                title: Text(
                  entry.name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: entry.isFile
                    ? Text(
                        HashUtils.formatBytes(entry.size),
                        style: const TextStyle(fontSize: 11, color: FiloColors.lightTextTertiary),
                      )
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}
