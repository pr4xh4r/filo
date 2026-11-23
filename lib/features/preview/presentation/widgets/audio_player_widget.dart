import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_typography.dart';

/// Apple iOS Music-inspired audio player.
class AudioPlayerWidget extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;
  final int sizeBytes;

  const AudioPlayerWidget({
    super.key,
    required this.bytes,
    required this.fileName,
    required this.sizeBytes,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget>
    with SingleTickerProviderStateMixin {
  late AudioPlayer _player;
  late AnimationController _rotationController;
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    _initAudio();
  }

  Future<void> _initAudio() async {
    _player = AudioPlayer();
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playerState = state);
      if (state == PlayerState.playing) {
        _rotationController.repeat();
      } else {
        _rotationController.stop();
      }
    });

    _player.onDurationChanged.listen((dur) {
      if (!mounted) return;
      setState(() => _duration = dur);
    });

    _player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });

    try {
      await _player.setSource(BytesSource(widget.bytes));
    } catch (e) {
      setState(() {
        _error = 'Audio playback error: $e';
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
              const Icon(Icons.music_off_outlined, size: 48, color: FiloColors.destructive),
              const SizedBox(height: 12),
              Text('Unable to play audio', style: FiloTypography.title3),
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(fontSize: 12, color: FiloColors.lightTextTertiary), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    final isPlaying = _playerState == PlayerState.playing;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Rotating Vinyl Disc
              RotationTransition(
                turns: _rotationController,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFF2C2C2E), Color(0xFF1C1C1E)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: FiloColors.primary.withValues(alpha: 0.2),
                        border: Border.all(color: Colors.white30, width: 2),
                      ),
                      child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 24),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                widget.fileName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: FiloTypography.title2.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                HashUtils.formatBytes(widget.sizeBytes),
                style: const TextStyle(fontSize: 13, color: FiloColors.lightTextTertiary),
              ),

              const SizedBox(height: 24),

              // Progress Slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: FiloColors.primary,
                  inactiveTrackColor: FiloColors.primary.withValues(alpha: 0.15),
                  thumbColor: FiloColors.primary,
                ),
                child: Slider(
                  value: _duration.inMilliseconds > 0
                      ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                      : 0.0,
                  onChanged: (val) {
                    final target = Duration(
                      milliseconds: (val * _duration.inMilliseconds).round(),
                    );
                    _player.seek(target);
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: const TextStyle(fontSize: 12, color: FiloColors.lightTextTertiary),
                    ),
                    Text(
                      _formatDuration(_duration),
                      style: const TextStyle(fontSize: 12, color: FiloColors.lightTextTertiary),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Controls: -10s, Play/Pause, +10s
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.replay_10_rounded, size: 28),
                    color: FiloColors.lightTextPrimary,
                    onPressed: () {
                      final newPos = _position - const Duration(seconds: 10);
                      _player.seek(newPos < Duration.zero ? Duration.zero : newPos);
                    },
                  ),
                  const SizedBox(width: 20),
                  GestureDetector(
                    onTap: () {
                      if (isPlaying) {
                        _player.pause();
                      } else {
                        _player.resume();
                      }
                    },
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    icon: const Icon(Icons.forward_10_rounded, size: 28),
                    color: FiloColors.lightTextPrimary,
                    onPressed: () {
                      final newPos = _position + const Duration(seconds: 10);
                      _player.seek(newPos > _duration ? _duration : newPos);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
