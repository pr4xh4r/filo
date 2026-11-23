import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/theme/filo_colors.dart';

/// Lightweight, hardware-accelerated video player with custom touch controls.
class VideoPlayerWidget extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;

  const VideoPlayerWidget({
    super.key,
    required this.bytes,
    required this.fileName,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _controller;
  File? _tempFile;
  bool _isInitialized = false;
  bool _showControls = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final ext = widget.fileName.contains('.') ? widget.fileName.split('.').last : 'mp4';
      _tempFile = File(
        '${tempDir.path}/filo_vid_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await _tempFile!.writeAsBytes(widget.bytes, flush: true);

      _controller = VideoPlayerController.file(_tempFile!)
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {
            _isInitialized = true;
          });
          _controller!.play();
        }).catchError((e) {
          if (!mounted) return;
          setState(() => _error = 'Failed to load video: $e');
        });

      _controller!.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (e) {
      setState(() => _error = 'Video initialization error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _tempFile?.delete().ignore();
    super.dispose();
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
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
              const Icon(Icons.videocam_off_outlined, size: 48, color: FiloColors.destructive),
              const SizedBox(height: 12),
              const Text('Unable to play video', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: FiloColors.lightTextTertiary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return const Center(
        child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(FiloColors.primary)),
      );
    }

    final isPlaying = _controller!.value.isPlaying;
    final position = _controller!.value.position;
    final duration = _controller!.value.duration;

    return Center(
      child: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(_controller!),
                if (_showControls) ...[
                  Container(color: Colors.black26),
                  GestureDetector(
                    onTap: () {
                      if (isPlaying) {
                        _controller!.pause();
                      } else {
                        _controller!.play();
                      }
                    },
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VideoProgressIndicator(
                            _controller!,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: FiloColors.primary,
                              bufferedColor: Colors.white24,
                              backgroundColor: Colors.white10,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_format(position)} / ${_format(duration)}',
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                              ),
                              IconButton(
                                icon: Icon(
                                  _controller!.value.volume > 0
                                      ? Icons.volume_up_rounded
                                      : Icons.volume_off_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                onPressed: () {
                                  _controller!.setVolume(
                                    _controller!.value.volume > 0 ? 0 : 1,
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
