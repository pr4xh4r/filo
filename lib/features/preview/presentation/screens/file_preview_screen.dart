import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/cache/session_cache_service.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/database/chunk_model.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_background.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../files/domain/workspace.dart';
import '../../../files/presentation/providers/file_browser_provider.dart';
import '../../../transfer/presentation/providers/transfer_provider.dart';
import '../widgets/archive_inspector_widget.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/code_text_viewer_widget.dart';
import '../widgets/csv_table_viewer_widget.dart';
import '../widgets/pdf_viewer_widget.dart';
import '../widgets/video_player_widget.dart';

/// Top-level helper function for AES-256-GCM chunk decryption.
/// Being top-level ensures it never captures [State], [Widget], or [BuildContext] references.
Future<Uint8List> _previewDecryptInIsolate(
  Uint8List combinedBytes,
  Uint8List key,
) {
  return Isolate.run(() => CryptoEngine.decryptBytes(
    combinedBytes: combinedBytes,
    key: key,
  ));
}

/// Previews decrypted media, text, documents, or shows a rich metadata fallback viewer.
/// Supports uninterrupted horizontal swiping across sibling photos, videos, and documents.
class FilePreviewScreen extends ConsumerStatefulWidget {
  final FileNode? node;
  final List<FileNode>? siblingNodes;
  final int initialIndex;

  const FilePreviewScreen({
    super.key,
    this.node,
    this.siblingNodes,
    this.initialIndex = 0,
  });

  @override
  ConsumerState<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends ConsumerState<FilePreviewScreen> {
  late final List<FileNode> _nodes;
  late final PageController _pageController;
  late int _currentIndex;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    if (widget.siblingNodes != null && widget.siblingNodes!.isNotEmpty) {
      _nodes = List<FileNode>.from(widget.siblingNodes!);
      _currentIndex = widget.initialIndex.clamp(0, _nodes.length - 1);
    } else if (widget.node != null) {
      _nodes = [widget.node!];
      _currentIndex = 0;
    } else {
      _nodes = [];
      _currentIndex = 0;
    }
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_nodes.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No file to preview')),
      );
    }

    final currentNode = _nodes[_currentIndex];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF14141F) : FiloColors.lightBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF222234) : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 14,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currentNode.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FiloTypography.title3.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : FiloColors.lightTextPrimary,
              ),
            ),
            if (_nodes.length > 1) ...[
              const SizedBox(height: 2),
              Text(
                '${_currentIndex + 1} of ${_nodes.length}',
                style: TextStyle(
                  fontFamily: FiloTypography.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                ),
              ),
            ],
          ],
        ),
        actions: [
          // Favorite Toggle
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF222234) : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Icon(
                currentNode.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                size: 16,
                color: currentNode.isFavorite ? FiloColors.accentCoral : (isDark ? Colors.white : Colors.black),
              ),
            ),
            tooltip: currentNode.isFavorite ? 'Remove from Starred' : 'Add to Starred',
            onPressed: () {
              HapticFeedback.lightImpact();
              ref.read(fileBrowserProvider.notifier).toggleFavorite(
                    currentNode.id,
                    !currentNode.isFavorite,
                  );
              setState(() {
                _nodes[_currentIndex] = currentNode.copyWith(
                  isFavorite: !currentNode.isFavorite,
                );
              });
            },
          ),
          const SizedBox(width: 4),

          // Share Decrypted Copy
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF222234) : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Icon(
                Icons.share_rounded,
                size: 16,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            tooltip: 'Share Decrypted Copy',
            onPressed: () {
              HapticFeedback.selectionClick();
              ref
                  .read(transferQueueProvider.notifier)
                  .shareDecryptedCopy(currentNode);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FiloBackground(
        child: _nodes.length == 1
            ? SingleFilePreviewWidget(node: _nodes.first)
            : PageView.builder(
                controller: _pageController,
                itemCount: _nodes.length,
                physics: _isZoomed
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                onPageChanged: (index) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _currentIndex = index;
                    _isZoomed = false;
                  });
                },
                itemBuilder: (context, index) {
                  return SingleFilePreviewWidget(
                    key: ValueKey(_nodes[index].id),
                    node: _nodes[index],
                    isActive: _currentIndex == index,
                    onZoomChanged: (zoomed) {
                      if (_isZoomed != zoomed) {
                        setState(() => _isZoomed = zoomed);
                      }
                    },
                  );
                },
              ),
      ),
    );
  }
}

/// Standalone preview page for an individual decrypted file node.
class SingleFilePreviewWidget extends ConsumerStatefulWidget {
  final FileNode node;
  final ValueChanged<bool>? onZoomChanged;
  final bool isActive;

  const SingleFilePreviewWidget({
    super.key,
    required this.node,
    this.onZoomChanged,
    this.isActive = true,
  });

  @override
  ConsumerState<SingleFilePreviewWidget> createState() => _SingleFilePreviewWidgetState();
}

class _SingleFilePreviewWidgetState extends ConsumerState<SingleFilePreviewWidget>
    with AutomaticKeepAliveClientMixin {
  late final TransformationController _transformationController;
  bool _isLoading = true;
  Uint8List? _decryptedBytes;
  File? _videoFile;
  File? _pdfFile;
  File? _imageFile;
  String? _textContent;
  String? _errorMessage;
  double _loadProgress = 0.0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _loadAndDecryptFile();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _loadAndDecryptFile() async {
    setState(() {
      _isLoading = true;
      _loadProgress = 0.0;
    });
    try {
      final authState = ref.read(authNotifierProvider);
      final masterKey = authState.masterKey;
      if (masterKey == null) {
        throw Exception('Vault locked');
      }

      final fileRepo = ref.read(fileRepositoryProvider);

      final name = widget.node.name.toLowerCase();
      final mime = widget.node.mimeType?.toLowerCase() ?? '';
      final isVideo = mime.startsWith('video/') ||
          name.endsWith('.mp4') ||
          name.endsWith('.mkv') ||
          name.endsWith('.mov') ||
          name.endsWith('.avi') ||
          name.endsWith('.webm');
      final isPdf = mime == 'application/pdf' || name.endsWith('.pdf');
      final isImage = mime.startsWith('image/') ||
          name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.png') ||
          name.endsWith('.webp') ||
          name.endsWith('.gif') ||
          name.endsWith('.bmp');
      final isText = mime.startsWith('text/') ||
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
          name.endsWith('.sh');

      // 1. Instant 0ms Load from Persistent Offline Pin (if saved offline)
      final offlineFile = await fileRepo.getOfflineFile(widget.node.id);
      if (offlineFile != null && offlineFile.existsSync() && offlineFile.lengthSync() > 0) {
        if (isVideo) {
          _videoFile = offlineFile;
        } else if (isPdf) {
          _pdfFile = offlineFile;
        } else if (isImage) {
          _imageFile = offlineFile;
        } else {
          _decryptedBytes = await offlineFile.readAsBytes();
          if (isText) {
            _textContent = utf8.decode(_decryptedBytes!, allowMalformed: true);
          }
        }
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 2. Instant 0ms Load from Secure Session Cache (if viewed previously in current session)
      final cachedSessionFile = await SessionCacheService.instance.getCachedFile(
        widget.node.id,
        expectedSize: widget.node.sizeBytes,
      );
      if (cachedSessionFile != null) {
        if (isVideo) {
          _videoFile = cachedSessionFile;
        } else if (isPdf) {
          _pdfFile = cachedSessionFile;
        } else if (isImage) {
          _imageFile = cachedSessionFile;
        } else {
          _decryptedBytes = await cachedSessionFile.readAsBytes();
          if (isText) {
            _textContent = utf8.decode(_decryptedBytes!, allowMalformed: true);
          }
        }
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 3. Download from Telegram and Stream Decrypt Directly into Session Cache
      final chunks = await fileRepo.getChunksForNode(widget.node.id);
      final storage = ref.read(storageBackendProvider);

      // Determine correct Telegram channel (filo enc vs filo view)
      final workspaces = await fileRepo.getWorkspaces();
      final ws = workspaces.firstWhere(
        (w) => w.id == widget.node.workspaceId,
        orElse: () => Workspace.fromId(widget.node.workspaceId, workspaces),
      );
      final channelTitle = AppConfig.getChannelTitle(isEncrypted: ws.isEncrypted);
      final channel = await storage.getOrCreateVaultChannel(channelTitle);

      final ext = name.contains('.') ? name.split('.').last : (isVideo ? 'mp4' : 'bin');
      final targetSessionFile = await SessionCacheService.instance.getSessionFile(widget.node.id, ext);
      if (targetSessionFile.existsSync()) {
        try {
          targetSessionFile.deleteSync();
        } catch (_) {}
      }

      if (chunks.isNotEmpty) {
        final sortedChunks = List<FileChunk>.from(chunks)
          ..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
        final sink = targetSessionFile.openWrite();
        try {
          int done = 0;
          for (final c in sortedChunks) {
            final chunkCipher = await storage.downloadChunk(
              channelId: channel.channelId,
              remoteFileId: c.remoteFileId,
            );
            final downloadedHash = HashUtils.sha256Hex(chunkCipher);
            if (downloadedHash != c.sha256Hash) {
              throw Exception('Chunk integrity check failed for part ${c.chunkIndex}');
            }
            final chunkData = (c.ivHex == 'plain')
                ? chunkCipher
                : await _previewDecryptInIsolate(chunkCipher, masterKey);
            sink.add(chunkData);
            done++;
            if (mounted) {
              setState(() => _loadProgress = done / sortedChunks.length);
            }
          }
        } finally {
          await sink.flush();
          await sink.close();
        }
      } else {
        await targetSessionFile.writeAsBytes(utf8.encode('Placeholder content'));
      }

      // Run LRU pass to keep disk space and memory bounded
      await SessionCacheService.instance.evictLruIfNeeded();

      if (isVideo) {
        _videoFile = targetSessionFile;
      } else if (isPdf) {
        _pdfFile = targetSessionFile;
      } else if (isImage) {
        _imageFile = targetSessionFile;
      } else {
        _decryptedBytes = await targetSessionFile.readAsBytes();
        if (isText) {
          _textContent = utf8.decode(_decryptedBytes!, allowMalformed: true);
        }
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final name = widget.node.name.toLowerCase();
    final mime = widget.node.mimeType?.toLowerCase() ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget content;

    if (_isLoading) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(FiloColors.primary),
            ),
            if (_loadProgress > 0) ...[
              const SizedBox(height: 16),
              Text(
                'Decrypting ${(_loadProgress * 100).toInt()}%...',
                style: const TextStyle(
                  fontFamily: FiloTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: FiloColors.lightTextSecondary,
                ),
              ),
            ],
          ],
        ),
      );
    } else if (_errorMessage != null) {
      content = Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FiloSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
        (_imageFile != null || _decryptedBytes != null)) {
      // 1. Interactive Zoomable Image Preview with Pan/Zoom detection for PageView
      content = InteractiveViewer(
        transformationController: _transformationController,
        panEnabled: true,
        boundaryMargin: const EdgeInsets.all(20),
        minScale: 1.0,
        maxScale: 4.0,
        onInteractionEnd: (_) {
          final scale = _transformationController.value.getMaxScaleOnAxis();
          widget.onZoomChanged?.call(scale > 1.05);
        },
        child: Center(
          child: _imageFile != null
              ? Image.file(
                  _imageFile!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_rounded,
                    size: 64,
                  ),
                )
              : Image.memory(
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
        (_pdfFile != null || _decryptedBytes != null)) {
      // 2. Native Multi-Page PDF Viewer
      content = PdfViewerWidget(
        file: _pdfFile,
        bytes: _decryptedBytes,
        fileName: widget.node.name,
      );
    } else if ((mime.startsWith('video/') ||
            name.endsWith('.mp4') ||
            name.endsWith('.mkv') ||
            name.endsWith('.mov') ||
            name.endsWith('.avi') ||
            name.endsWith('.webm')) &&
        (_videoFile != null || _decryptedBytes != null)) {
      // 3. Hardware-Accelerated Video Player
      content = VideoPlayerWidget(
        file: _videoFile,
        bytes: _decryptedBytes,
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
      // 7. Interactive Code & Text Viewer
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
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : FiloColors.primary.withValues(alpha: 0.1),
                  borderRadius: FiloRadius.roundedXl,
                ),
                child: Icon(
                  Icons.insert_drive_file_rounded,
                  size: 40,
                  color: isDark ? Colors.white : FiloColors.primary,
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
                style: TextStyle(
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
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

    return content;
  }
}
