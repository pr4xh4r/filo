import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../files/presentation/providers/file_browser_provider.dart';
import '../../../transfer/presentation/providers/transfer_provider.dart';

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
        final bytesBuilder = BytesBuilder();
        for (final c in chunks) {
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
        _decryptedBytes = Uint8List.fromList(utf8.encode('Encrypted content for ${widget.node.name}'));
      }

      final mime = widget.node.mimeType?.toLowerCase() ?? '';
      if (mime.startsWith('text/') ||
          mime.contains('json') ||
          mime.contains('dart') ||
          mime.contains('javascript') ||
          mime.contains('xml') ||
          mime.contains('yaml')) {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
              const Icon(Icons.error_outline_rounded, size: 48, color: FiloColors.destructive),
              const SizedBox(height: FiloSpacing.md),
              const Text('Decryption Failed', style: FiloTypography.title2),
              const SizedBox(height: FiloSpacing.xs),
              Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      );
    } else if (mime.startsWith('image/') && _decryptedBytes != null) {
      // Interactive Zoomable Image Preview
      content = InteractiveViewer(
        panEnabled: true,
        boundaryMargin: const EdgeInsets.all(20),
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: Image.memory(
            _decryptedBytes!,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, size: 64),
          ),
        ),
      );
    } else if (_textContent != null) {
      // Text & Code Viewer
      content = SingleChildScrollView(
        padding: const EdgeInsets.all(FiloSpacing.lg),
        child: SelectableText(
          _textContent!,
          style: FiloTypography.monospace.copyWith(
            color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      );
    } else {
      // Rich Metadata Fallback Viewer
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(FiloSpacing.xxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: FiloColors.primary.withValues(alpha: 0.1),
                  borderRadius: FiloRadius.roundedXl,
                ),
                child: const Icon(
                  Icons.insert_drive_file_rounded,
                  size: 36,
                  color: FiloColors.primary,
                ),
              ),
              const SizedBox(height: FiloSpacing.lg),
              Text(
                widget.node.name,
                textAlign: TextAlign.center,
                style: FiloTypography.title2,
              ),
              const SizedBox(height: FiloSpacing.xs),
              Text(
                '${HashUtils.formatBytes(widget.node.sizeBytes)} • ${widget.node.mimeType ?? 'Unknown Type'}',
                style: TextStyle(
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: FiloSpacing.xl),
              FiloButton(
                label: 'Share Decrypted Copy',
                icon: const Icon(Icons.share_rounded, size: 18),
                onPressed: () {
                  ref.read(transferQueueProvider.notifier).shareDecryptedCopy(widget.node);
                },
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.node.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share Decrypted Copy',
            onPressed: () {
              ref.read(transferQueueProvider.notifier).shareDecryptedCopy(widget.node);
            },
          ),
        ],
      ),
      body: content,
    );
  }
}
