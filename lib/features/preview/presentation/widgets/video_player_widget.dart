import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_typography.dart';

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

/// Rich, hardware-accelerated video player with custom touch controls,
/// scrubbing, 10s skip, playback speed, double-tap seek, and fullscreen mode.
class VideoPlayerWidget extends StatefulWidget {
  final Uint8List? bytes;
  final File? file;
  final String fileName;

  const VideoPlayerWidget({
    super.key,
    this.bytes,
    this.file,
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
  Timer? _hideControlsTimer;
  String? _error;
  double _playbackSpeed = 1.0;
  bool _isSeeking = false;
  double _dragValue = 0.0;
  String? _seekFeedback; // '+10s' or '-10s'
  Timer? _feedbackTimer;

  static const List<double> _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      if (widget.file != null && widget.file!.existsSync()) {
        _tempFile = widget.file;
      } else if (widget.bytes != null) {
        final tempDir = await getTemporaryDirectory();
        final ext = widget.fileName.contains('.') ? widget.fileName.split('.').last : 'mp4';
        _tempFile = File(
          '${tempDir.path}/filo_vid_${DateTime.now().millisecondsSinceEpoch}.$ext',
        );
        await _tempFile!.writeAsBytes(widget.bytes!, flush: true);
      } else {
        throw Exception('No video file or bytes provided');
      }

      _controller = VideoPlayerController.file(_tempFile!)
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {
            _isInitialized = true;
          });
          _controller!.play();
          _startHideTimer();
        }).catchError((e) {
          if (!mounted) return;
          setState(() => _error = 'Failed to load video: $e');
        });

      _controller!.addListener(() {
        if (mounted && !_isSeeking) setState(() {});
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Video initialization error: $e');
    }
  }

  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    if (_controller != null && _controller!.value.isPlaying) {
      _hideControlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _controller != null && _controller!.value.isPlaying && !_isSeeking) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _startHideTimer();
      } else {
        _hideControlsTimer?.cancel();
      }
    });
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    HapticFeedback.lightImpact();
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      _hideControlsTimer?.cancel();
      setState(() => _showControls = true);
    } else {
      _controller!.play();
      _startHideTimer();
      setState(() {});
    }
  }

  void _seekRelative(int seconds) {
    if (_controller == null || !_isInitialized) return;
    HapticFeedback.lightImpact();
    final current = _controller!.value.position;
    final target = current + Duration(seconds: seconds);
    final clamped = Duration(
      milliseconds: target.inMilliseconds.clamp(0, _controller!.value.duration.inMilliseconds),
    );
    _controller!.seekTo(clamped);

    _showFeedback(seconds > 0 ? '+${seconds}s' : '${seconds}s');
    _startHideTimer();
  }

  void _showFeedback(String text) {
    _feedbackTimer?.cancel();
    setState(() => _seekFeedback = text);
    _feedbackTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekFeedback = null);
    });
  }

  void _cycleSpeed() {
    if (_controller == null || !_isInitialized) return;
    HapticFeedback.selectionClick();
    final currentIndex = _speeds.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % _speeds.length;
    final nextSpeed = _speeds[nextIndex];
    _controller!.setPlaybackSpeed(nextSpeed);
    setState(() => _playbackSpeed = nextSpeed);
    _startHideTimer();
  }

  void _openFullScreen() {
    if (_controller == null || !_isInitialized) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullScreenVideoScreen(
          controller: _controller!,
          fileName: widget.fileName,
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {});
        _startHideTimer();
      }
    });
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _feedbackTimer?.cancel();
    _controller?.dispose();
    if (widget.bytes != null && widget.file == null) {
      _tempFile?.delete().ignore();
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
              const Icon(Icons.videocam_off_outlined, size: 48, color: FiloColors.destructive),
              const SizedBox(height: 12),
              const Text(
                'Unable to play video',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
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
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(FiloColors.primary),
        ),
      );
    }

    final isPlaying = _controller!.value.isPlaying;
    final position = _controller!.value.position;
    final duration = _controller!.value.duration;
    final currentPosMs = _isSeeking ? _dragValue : position.inMilliseconds.toDouble();
    final totalMs = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: _controller!.value.aspectRatio > 0 ? _controller!.value.aspectRatio : 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              // 1. Raw Video View
              VideoPlayer(_controller!),

              // 2. Gesture Detector for Tap & Double-Tap (Left = -10s, Right = +10s)
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _toggleControls,
                        onDoubleTap: () => _seekRelative(-10),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _toggleControls,
                        onDoubleTap: () => _seekRelative(10),
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Transient Feedback Bubble for Double-Tap Seek
              if (_seekFeedback != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _seekFeedback!.startsWith('+') ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _seekFeedback!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 4. Sleek Controls Overlay
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleControls,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.55),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.85),
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Top Bar: Video File Name
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                              child: Row(
                                children: [
                                  const Icon(Icons.videocam_rounded, color: Colors.white70, size: 15),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      widget.fileName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: FiloTypography.fontFamily,
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Center Controls: Rewind 10s, Play/Pause, Forward 10s
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 28),
                                tooltip: 'Rewind 10s',
                                onPressed: () => _seekRelative(-10),
                              ),
                              const SizedBox(width: 14),
                              GestureDetector(
                                onTap: _togglePlayPause,
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white30, width: 1.5),
                                  ),
                                  child: Icon(
                                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 28),
                                tooltip: 'Forward 10s',
                                onPressed: () => _seekRelative(10),
                              ),
                            ],
                          ),
                        ),

                        // Bottom Bar: Scrubber, Duration, Speed, Mute, Fullscreen
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Scrubber Slider
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 2.5,
                                    activeTrackColor: Colors.white,
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: Colors.white,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10.0),
                                  ),
                                  child: Slider(
                                    value: currentPosMs.clamp(0.0, totalMs),
                                    min: 0.0,
                                    max: totalMs,
                                    onChangeStart: (_) {
                                      setState(() => _isSeeking = true);
                                      _hideControlsTimer?.cancel();
                                    },
                                    onChanged: (val) {
                                      setState(() => _dragValue = val);
                                    },
                                    onChangeEnd: (val) {
                                      _controller!.seekTo(Duration(milliseconds: val.toInt()));
                                      setState(() => _isSeeking = false);
                                      _startHideTimer();
                                    },
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      '${_formatDuration(position)} / ${_formatDuration(duration)}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),

                                    // Playback Speed Button
                                    GestureDetector(
                                      onTap: _cycleSpeed,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(5),
                                          border: Border.all(color: Colors.white24),
                                        ),
                                        child: Text(
                                          '${_playbackSpeed}x',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),

                                    // Audio Mute Toggle
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                      icon: Icon(
                                        _controller!.value.volume > 0
                                            ? Icons.volume_up_rounded
                                            : Icons.volume_off_rounded,
                                        color: Colors.white,
                                        size: 17,
                                      ),
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        _controller!.setVolume(
                                          _controller!.value.volume > 0 ? 0 : 1,
                                        );
                                        setState(() {});
                                      },
                                    ),
                                    const SizedBox(width: 2),

                                    // Fullscreen Button
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                      icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 20),
                                      onPressed: _openFullScreen,
                                    ),
                                  ],
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
            ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dedicated immersive edge-to-edge full-screen video player.
class FullScreenVideoScreen extends StatefulWidget {
  final VideoPlayerController controller;
  final String fileName;

  const FullScreenVideoScreen({
    super.key,
    required this.controller,
    required this.fileName,
  });

  @override
  State<FullScreenVideoScreen> createState() => _FullScreenVideoScreenState();
}

class _FullScreenVideoScreenState extends State<FullScreenVideoScreen> {
  bool _showControls = true;
  Timer? _hideControlsTimer;
  bool _isSeeking = false;
  double _dragValue = 0.0;
  double _playbackSpeed = 1.0;
  bool _isLandscape = true;
  String? _seekFeedback;
  Timer? _feedbackTimer;

  static const List<double> _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    // Default to landscape and immersive mode
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    widget.controller.addListener(_controllerListener);
    _playbackSpeed = widget.controller.value.playbackSpeed;
    _startHideTimer();
  }

  void _controllerListener() {
    if (mounted && !_isSeeking) setState(() {});
  }

  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    if (widget.controller.value.isPlaying) {
      _hideControlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && widget.controller.value.isPlaying && !_isSeeking) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _startHideTimer();
      } else {
        _hideControlsTimer?.cancel();
      }
    });
  }

  void _togglePlayPause() {
    HapticFeedback.lightImpact();
    if (widget.controller.value.isPlaying) {
      widget.controller.pause();
      _hideControlsTimer?.cancel();
      setState(() => _showControls = true);
    } else {
      widget.controller.play();
      _startHideTimer();
      setState(() {});
    }
  }

  void _seekRelative(int seconds) {
    HapticFeedback.lightImpact();
    final current = widget.controller.value.position;
    final target = current + Duration(seconds: seconds);
    final clamped = Duration(
      milliseconds: target.inMilliseconds.clamp(0, widget.controller.value.duration.inMilliseconds),
    );
    widget.controller.seekTo(clamped);

    _showFeedback(seconds > 0 ? '+${seconds}s' : '${seconds}s');
    _startHideTimer();
  }

  void _showFeedback(String text) {
    _feedbackTimer?.cancel();
    setState(() => _seekFeedback = text);
    _feedbackTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekFeedback = null);
    });
  }

  void _cycleSpeed() {
    HapticFeedback.selectionClick();
    final currentIndex = _speeds.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % _speeds.length;
    final nextSpeed = _speeds[nextIndex];
    widget.controller.setPlaybackSpeed(nextSpeed);
    setState(() => _playbackSpeed = nextSpeed);
    _startHideTimer();
  }

  void _toggleOrientation() {
    HapticFeedback.selectionClick();
    setState(() {
      _isLandscape = !_isLandscape;
      if (_isLandscape) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerListener);
    _hideControlsTimer?.cancel();
    _feedbackTimer?.cancel();

    // Restore portrait and standard system UI mode
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = widget.controller.value.isPlaying;
    final position = widget.controller.value.position;
    final duration = widget.controller.value.duration;
    final currentPosMs = _isSeeking ? _dragValue : position.inMilliseconds.toDouble();
    final totalMs = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Centered Full-Bleed Video Player
          Center(
            child: AspectRatio(
              aspectRatio: widget.controller.value.aspectRatio > 0 ? widget.controller.value.aspectRatio : 16 / 9,
              child: VideoPlayer(widget.controller),
            ),
          ),

          // 2. Gesture Detector for Tap & Double-Tap (Rewind / Fast Forward)
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _toggleControls,
                    onDoubleTap: () => _seekRelative(-10),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _toggleControls,
                    onDoubleTap: () => _seekRelative(10),
                  ),
                ),
              ],
            ),
          ),

          // 3. Transient Double-Tap Feedback
          if (_seekFeedback != null)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _seekFeedback!.startsWith('+') ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _seekFeedback!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 4. Immersive Controls Overlay
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.70),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.85),
                      ],
                      stops: const [0.0, 0.40, 1.0],
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top Bar
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                                tooltip: 'Exit Fullscreen',
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: FiloTypography.fontFamily,
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.screen_rotation_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                tooltip: 'Rotate Screen',
                                onPressed: _toggleOrientation,
                              ),
                            ],
                          ),
                        ),

                      // Center Controls: Large Replay, Play/Pause, Forward
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 40),
                            tooltip: 'Rewind 10s',
                            onPressed: () => _seekRelative(-10),
                          ),
                          const SizedBox(width: 32),
                          GestureDetector(
                            onTap: _togglePlayPause,
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white38, width: 2),
                              ),
                              child: Icon(
                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 44,
                              ),
                            ),
                          ),
                          const SizedBox(width: 32),
                          IconButton(
                            icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 40),
                            tooltip: 'Forward 10s',
                            onPressed: () => _seekRelative(10),
                          ),
                        ],
                      ),

                      // Bottom Bar: Full Scrubber, Timestamps, Speed, Mute, Exit
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4.0,
                                activeTrackColor: Colors.white,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.0),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
                              ),
                              child: Slider(
                                value: currentPosMs.clamp(0.0, totalMs),
                                min: 0.0,
                                max: totalMs,
                                onChangeStart: (_) {
                                  setState(() => _isSeeking = true);
                                  _hideControlsTimer?.cancel();
                                },
                                onChanged: (val) {
                                  setState(() => _dragValue = val);
                                },
                                onChangeEnd: (val) {
                                  widget.controller.seekTo(Duration(milliseconds: val.toInt()));
                                  setState(() => _isSeeking = false);
                                  _startHideTimer();
                                },
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  '${_formatDuration(position)} / ${_formatDuration(duration)}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: _cycleSpeed,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: Text(
                                      '${_playbackSpeed}x',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton(
                                  icon: Icon(
                                    widget.controller.value.volume > 0
                                        ? Icons.volume_up_rounded
                                        : Icons.volume_off_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    widget.controller.setVolume(
                                      widget.controller.value.volume > 0 ? 0 : 1,
                                    );
                                    setState(() {});
                                  },
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white, size: 24),
                                  tooltip: 'Exit Fullscreen',
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }
}
