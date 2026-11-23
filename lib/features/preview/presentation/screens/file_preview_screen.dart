import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/database/chunk_model.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../files/presentation/providers/file_browser_provider.dart';
import '../../../transfer/presentation/providers/transfer_provider.dart';
import '../widgets/archive_inspector_widget.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/code_text_viewer_widget.dart';
import '../widgets/csv_table_viewer_widget.dart';
import '../widgets/pdf_viewer_widget.dart';
import '../widgets/video_player_widget.dart';

/// Previews decrypted media, text, documents, or shows a rich metadata fallback viewer.
class FilePreviewScreen extends ConsumerStatefulWidget {
  final FileNode node;

  const FilePreviewScreen({super.key, required this.node});

  @override
  ConsumerState<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends ConsumerState<FilePreviewScreen> {
  bool _isLoading = true;
  Uint8List? _decryptedBytes;
  String? _textContent;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAndDecryptFile();
  }

  Future<void> _loadAndDecryptFile() async {
    setState(() => _isLoading = true);
    try {
      final authState = ref.read(authNotifierProvider);
      final masterKey = authState.masterKey;
      if (masterKey == null) {
        throw Exception('Vault locked');
      }

      final fileRepo = ref.read(fileRepositoryProvider);
      final chunks = await fileRepo.getChunksForNode(widget.node.id);
      final storage = ref.read(storageBackendProvider);
      final channel = await storage.getOrCreateVaultChannel('');

      if (chunks.isNotEmpty) {
        final sortedChunks = List<FileChunk>.from(chunks)
          ..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
        final bytesBuilder = BytesBuilder();
        for (final c in sortedChunks) {
          final chunkCipher = await storage.downloadChunk(
            channelId: channel.channelId,
            remoteFileId: c.remoteFileId,
          );
          final decrypted = await CryptoEngine.decryptBytes(
            combinedBytes: chunkCipher,
            key: masterKey,
          );
          bytesBuilder.add(decrypted);
        }
        _decryptedBytes = bytesBuilder.toBytes();
      } else {
        _decryptedBytes = Uint8List.fromList(
          utf8.encode('Encrypted content for ${widget.node.name}'),
        );
      }

      final name = widget.node.name.toLowerCase();
      final mime = widget.node.mimeType?.toLowerCase() ?? '';

      // Check if it's text, code, or spreadsheet
      if (mime.startsWith('text/') ||
          name.endsWith('.txt') ||
          name.endsWith('.md') ||
          name.endsWith('.csv') ||
          name.endsWith('.tsv') ||
          name.endsWith('.json') ||
          name.endsWith('.dart') ||
          name.endsWith('.js') ||
          name.endsWith('.ts') ||
          name.endsWith('.py') ||
          name.endsWith('.yaml') ||
          name.endsWith('.yml') ||
          name.endsWith('.xml') ||
          name.endsWith('.html') ||
          name.endsWith('.css') ||
          name.endsWith('.sql') ||
          name.endsWith('.sh')) {
        _textContent = utf8.decode(_decryptedBytes!, allowMalformed: true);
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.node.name.toLowerCase();
    final mime = widget.node.mimeType?.toLowerCase() ?? '';

    Widget content;
    if (_isLoading) {
      content = const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(FiloColors.primary),
        ),
      );
    } else if (_errorMessage != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(FiloSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: FiloColors.destructive,
              ),
              const SizedBox(height: FiloSpacing.md),
              Text('Decryption Failed', style: FiloTypography.title2),
              const SizedBox(height: FiloSpacing.xs),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      );
    } else if ((mime.startsWith('image/') ||
            name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.png') ||
            name.endsWith('.webp') ||
            name.endsWith('.gif') ||
            name.endsWith('.bmp')) &&
        _decryptedBytes != null) {
      // 1. Interactive Zoomable Image Preview
      content = InteractiveViewer(
        panEnabled: true,
        boundaryMargin: const EdgeInsets.all(20),
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: Image.memory(
            _decryptedBytes!,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image_rounded,
              size: 64,
            ),
          ),
        ),
      );
    } else if ((mime == 'application/pdf' || name.endsWith('.pdf')) &&
        _decryptedBytes != null) {
      // 2. Native Multi-Page PDF Viewer
      content = PdfViewerWidget(
        bytes: _decryptedBytes!,
        fileName: widget.node.name,
      );
    } else if ((mime.startsWith('video/') ||
            name.endsWith('.mp4') ||
            name.endsWith('.mkv') ||
            name.endsWith('.mov') ||
            name.endsWith('.avi') ||
            name.endsWith('.webm')) &&
        _decryptedBytes != null) {
      // 3. Hardware-Accelerated Video Player
      content = VideoPlayerWidget(
        bytes: _decryptedBytes!,
        fileName: widget.node.name,
      );
    } else if ((mime.startsWith('audio/') ||
            name.endsWith('.mp3') ||
            name.endsWith('.wav') ||
            name.endsWith('.m4a') ||
            name.endsWith('.aac') ||
            name.endsWith('.flac') ||
            name.endsWith('.ogg')) &&
        _decryptedBytes != null) {
      // 4. Apple iOS Music-Style Audio Player
      content = AudioPlayerWidget(
        bytes: _decryptedBytes!,
        fileName: widget.node.name,
        sizeBytes: widget.node.sizeBytes,
      );
    } else if ((name.endsWith('.csv') || name.endsWith('.tsv')) &&
        _textContent != null) {
      // 5. Interactive CSV / TSV Spreadsheet Viewer
      content = CsvTableViewerWidget(
        content: _textContent!,
        fileName: widget.node.name,
      );
    } else if ((name.endsWith('.zip') || mime.contains('zip')) &&
        _decryptedBytes != null) {
      // 6. ZIP Archive Explorer & Inspector
      content = ArchiveInspectorWidget(
        bytes: _decryptedBytes!,
        fileName: widget.node.name,
      );
    } else if (_textContent != null) {
      // 7. Interactive Code & Text Viewer (Line Numbers, Copy, Wrap)
      content = CodeTextViewerWidget(
        text: _textContent!,
        fileName: widget.node.name,
      );
    } else {
      // 8. Rich Apple-Grade Metadata Fallback Viewer
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(FiloSpacing.xxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: FiloColors.primary.withValues(alpha: 0.1),
                  borderRadius: FiloRadius.roundedXl,
                ),
                child: const Icon(
                  Icons.insert_drive_file_rounded,
                  size: 40,
                  color: FiloColors.primary,
                ),
              ),
              const SizedBox(height: FiloSpacing.lg),
              Text(
                widget.node.name,
                textAlign: TextAlign.center,
                style: FiloTypography.title2.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: FiloSpacing.xs),
              Text(
                '${HashUtils.formatBytes(widget.node.sizeBytes)} • ${widget.node.mimeType ?? 'Binary Document'}',
                style: const TextStyle(
                  color: FiloColors.lightTextSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: FiloSpacing.xl),
              FiloButton(
                label: 'Share Decrypted Copy',
                icon: const Icon(Icons.share_rounded, size: 18),
                onPressed: () {
                  ref
                      .read(transferQueueProvider.notifier)
                      .shareDecryptedCopy(widget.node);
                },
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: FiloColors.lightBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 14,
              color: Colors.black,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.node.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FiloTypography.title3.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              ),
              child: const Icon(
                Icons.share_rounded,
                size: 16,
                color: Colors.black,
              ),
            ),
            tooltip: 'Share Decrypted Copy',
            onPressed: () {
              ref
                  .read(transferQueueProvider.notifier)
                  .shareDecryptedCopy(widget.node);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: content,
    );
  }
}
