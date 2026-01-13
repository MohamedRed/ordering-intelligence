import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'chat_audio_source.dart';

class ChatAudioPlayer extends StatefulWidget {
  const ChatAudioPlayer({
    super.key,
    required this.bytes,
    this.mimeType,
    this.foregroundColor,
    this.showLabel = true,
  });

  final Uint8List bytes;
  final String? mimeType;
  final Color? foregroundColor;
  final bool showLabel;

  @override
  State<ChatAudioPlayer> createState() => _ChatAudioPlayerState();
}

class _ChatAudioPlayerState extends State<ChatAudioPlayer> {
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<void>? _completeSub;

  bool _isPlaying = false;
  bool _completed = false;
  bool _loadingSource = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  ChatAudioSourceHandle? _sourceHandle;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      final playing = state == PlayerState.playing;
      if (mounted && playing != _isPlaying) {
        setState(() => _isPlaying = playing);
      }
    });
    _durationSub = _player.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _positionSub = _player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _completed = true;
        _position = Duration.zero;
      });
    });
  }

  @override
  void didUpdateWidget(ChatAudioPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _resetPlayer();
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _durationSub?.cancel();
    _positionSub?.cancel();
    _completeSub?.cancel();
    if (_sourceHandle != null) {
      unawaited(_sourceHandle!.dispose());
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (widget.bytes.isEmpty) return;
    if (_loadingSource) return;
    if (_isPlaying) {
      await _player.pause();
      return;
    }
    if (_sourceHandle == null || _completed) {
      setState(() => _loadingSource = true);
      ChatAudioSourceHandle handle;
      try {
        handle = await createChatAudioSourceHandle(
          widget.bytes,
          mimeType: widget.mimeType,
        );
      } catch (_) {
        if (mounted) setState(() => _loadingSource = false);
        return;
      }
      if (!mounted) {
        await handle.dispose();
        return;
      }
      final previous = _sourceHandle;
      _sourceHandle = handle;
      _completed = false;
      setState(() => _loadingSource = false);
      if (previous != null) {
        unawaited(previous.dispose());
      }
      await _player.play(handle.source);
      return;
    }
    await _player.resume();
  }

  void _resetPlayer() {
    unawaited(_player.stop());
    _completed = false;
    _loadingSource = false;
    _duration = Duration.zero;
    _position = Duration.zero;
    _isPlaying = false;
    final handle = _sourceHandle;
    if (handle != null) {
      unawaited(handle.dispose());
      _sourceHandle = null;
    }
  }

  String _format(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds % 60;
    final minutesLabel = minutes.toString().padLeft(2, '0');
    final secondsLabel = seconds.toString().padLeft(2, '0');
    return '$minutesLabel:$secondsLabel';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final color = widget.foregroundColor ?? theme.colorScheme.foreground;
    final durationLabel = _format(_duration);
    final positionLabel = _format(_position);
    final canPlay = widget.bytes.isNotEmpty && !_loadingSource;
    final iconColor = canPlay ? color : theme.colorScheme.mutedForeground;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_loadingSource)
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          )
        else
          IconButton(
            onPressed: canPlay ? _toggle : null,
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            icon: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: iconColor,
            ),
          ),
        if (widget.showLabel) ...[
          const SizedBox(width: 6),
          Text(
            'Voice message',
            style: theme.textTheme.small.copyWith(color: color),
          ),
        ],
        const SizedBox(width: 8),
        Text(
          '$positionLabel / $durationLabel',
          style: theme.textTheme.small.copyWith(color: color),
        ),
      ],
    );
  }
}
