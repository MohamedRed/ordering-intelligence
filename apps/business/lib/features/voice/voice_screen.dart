import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../providers/agent_customization_api.dart';
import '../../util/audio_player.dart';
import '../../util/audio_recorder.dart';
import '../../util/store_id.dart';
import '../../widgets/business_scaffold.dart';
import '../../widgets/shad_snackbar.dart';

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  static const _maxContentWidth = 920.0;

  late final String _storeId;

  bool _voiceLoading = false;
  bool _voiceSaving = false;
  bool _voiceApplying = false;
  bool _storeLoading = false;
  String? _voiceError;

  List<ElevenLabsVoice> _voiceOptions = const [];
  String? _voiceId;
  String? _voiceName;
  String? _appliedVoiceId;
  String? _appliedVoiceName;

  int _voiceCloneStep = 0;
  final _voiceNameCtrl = TextEditingController();
  final _voiceDescriptionCtrl = TextEditingController();
  bool _voiceRemoveNoise = true;
  bool _voiceConsent = false;
  final List<_VoiceSample> _voiceSamples = [];
  final List<_VoiceLabelRow> _voiceLabels = [];
  final AudioRecorder _recorder = createAudioRecorder();
  List<AudioInputDevice> _audioInputs = const [];
  String? _selectedAudioInputId;
  bool _recording = false;
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    _storeId = effectiveStoreId();
    _loadVoices();
    _loadStoreVoice();
    _loadAudioInputs();
    if (_voiceLabels.isEmpty) {
      _voiceLabels.add(_VoiceLabelRow(label: 'Language', value: 'English'));
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recorder.dispose();
    _voiceNameCtrl.dispose();
    _voiceDescriptionCtrl.dispose();
    for (final row in _voiceLabels) {
      row.dispose();
    }
    super.dispose();
  }

  String _resolveVoiceName(String voiceId) {
    final match = _voiceOptions
        .where((v) => v.id == voiceId)
        .map((v) => v.name)
        .where((v) => v.isNotEmpty)
        .toList();
    if (match.isNotEmpty) return match.first;
    return voiceId;
  }

  Future<void> _loadStoreVoice() async {
    if (_storeLoading) return;
    setState(() {
      _storeLoading = true;
      _voiceError = null;
    });
    try {
      final api = AgentCustomizationApi();
      final data = await api.getStoreVoice(_storeId);
      final voiceId = (data['voice_id'] as String?)?.trim() ?? '';
      if (!mounted) return;
      setState(() {
        _appliedVoiceId = voiceId.isEmpty ? null : voiceId;
        _appliedVoiceName = voiceId.isEmpty ? null : _resolveVoiceName(voiceId);
        if ((_voiceId ?? '').isEmpty && voiceId.isNotEmpty) {
          _voiceId = voiceId;
          _voiceName = _appliedVoiceName;
          _voiceNameCtrl.text = _voiceName ?? '';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiceError = e.toString());
    } finally {
      if (mounted) setState(() => _storeLoading = false);
    }
  }

  Future<void> _loadVoices() async {
    if (_voiceLoading) return;
    setState(() {
      _voiceLoading = true;
      _voiceError = null;
    });
    try {
      final api = AgentCustomizationApi();
      final voices = await api.listVoices();
      if (!mounted) return;
      setState(() {
        _voiceOptions = voices;
        if (_appliedVoiceId != null) {
          _appliedVoiceName = _resolveVoiceName(_appliedVoiceId!);
        }
        if (_voiceId != null) {
          _voiceName = _resolveVoiceName(_voiceId!);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiceError = e.toString());
    } finally {
      if (mounted) setState(() => _voiceLoading = false);
    }
  }

  Future<void> _loadAudioInputs() async {
    try {
      final devices = await _recorder.listInputs();
      if (!mounted) return;
      setState(() {
        _audioInputs = devices;
        if (_selectedAudioInputId == null && devices.isNotEmpty) {
          _selectedAudioInputId = devices.first.id;
        }
      });
    } catch (_) {
      // Default input fallback.
    }
  }

  Duration _totalRecordedDuration() {
    var total = Duration.zero;
    for (final sample in _voiceSamples) {
      total += sample.duration ?? Duration.zero;
    }
    return total;
  }

  String _formatClock(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _startRecording() async {
    if (_recording) return;
    setState(() => _voiceError = null);
    try {
      await _recorder.start(deviceId: _selectedAudioInputId);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordingElapsed = Duration.zero;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!_recording) {
          timer.cancel();
          return;
        }
        setState(() {
          _recordingElapsed += const Duration(seconds: 1);
        });
        if (_recordingElapsed.inSeconds >= 30) {
          _stopRecording();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiceError = e.toString());
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _recordingTimer?.cancel();
    try {
      final bytes = await _recorder.stop();
      if (!mounted) return;
      if (bytes.isEmpty) {
        setState(() => _recording = false);
        return;
      }
      final index = _voiceSamples.length + 1;
      final duration = _recordingElapsed;
      final sample = _VoiceSample(
        upload: VoiceSampleUpload(
          bytes: bytes,
          filename: 'Recording $index.webm',
          mimeType: 'audio/webm',
        ),
        displayName: 'Recording $index.mp4',
        duration: duration,
      );
      setState(() {
        _voiceSamples.add(sample);
        _recording = false;
        _recordingElapsed = Duration.zero;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _voiceError = e.toString();
      });
    }
  }

  Future<void> _applySelectedVoice() async {
    final voiceId = _voiceId?.trim() ?? '';
    if (voiceId.isEmpty) {
      showShadSnack(
        context,
        title: 'Select a voice',
        message: 'Choose a voice before applying.',
        type: ShadSnackType.warning,
      );
      return;
    }
    setState(() {
      _voiceApplying = true;
      _voiceError = null;
    });
    try {
      final api = AgentCustomizationApi();
      await api.setStoreVoice(storeId: _storeId, voiceId: voiceId);
      if (!mounted) return;
      setState(() {
        _appliedVoiceId = voiceId;
        _appliedVoiceName = _resolveVoiceName(voiceId);
      });
      showShadSnack(
        context,
        title: 'Voice applied',
        message: _appliedVoiceName,
        type: ShadSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiceError = e.toString());
    } finally {
      if (mounted) setState(() => _voiceApplying = false);
    }
  }

  Future<void> _createVoice() async {
    if (_voiceSaving) return;
    final name = _voiceNameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _voiceError = 'Provide a voice name.');
      return;
    }
    if (_voiceSamples.isEmpty) {
      setState(() => _voiceError = 'Upload at least one audio sample.');
      return;
    }
    if (_totalRecordedDuration().inSeconds < 10) {
      setState(() => _voiceError = 'Record at least 10 seconds of audio.');
      return;
    }
    if (!_voiceConsent) {
      setState(() => _voiceError = 'Confirm you have rights to use the audio.');
      return;
    }
    setState(() {
      _voiceSaving = true;
      _voiceError = null;
    });
    try {
      final labels = <String, dynamic>{};
      for (final row in _voiceLabels) {
        final label = row.labelCtrl.text.trim();
        final value = row.valueCtrl.text.trim();
        if (label.isNotEmpty && value.isNotEmpty) {
          labels[label] = value;
        }
      }
      final api = AgentCustomizationApi();
      final voice = await api.createVoice(
        name: name,
        description: _voiceDescriptionCtrl.text.trim(),
        labels: labels.isEmpty ? null : labels,
        files: _voiceSamples.map((e) => e.upload).toList(),
        removeBackgroundNoise: _voiceRemoveNoise,
      );
      if (!mounted) return;
      await api.setStoreVoice(storeId: _storeId, voiceId: voice.id);
      setState(() {
        _voiceId = voice.id;
        _voiceName = voice.name;
        _appliedVoiceId = voice.id;
        _appliedVoiceName = voice.name;
        _voiceCloneStep = 2;
      });
      await _loadVoices();
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiceError = e.toString());
    } finally {
      if (mounted) setState(() => _voiceSaving = false);
    }
  }

  Future<void> _previewVoice() async {
    final voiceId = _voiceId?.trim() ?? '';
    if (voiceId.isEmpty) return;
    try {
      final api = AgentCustomizationApi();
      final bytes = await api.previewVoice(
        voiceId: voiceId,
        text: 'Hello! This is a preview of the new voice.',
      );
      await playAudioBytes(bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiceError = e.toString());
    }
  }

  String _formatDuration(Duration d) {
    return _formatClock(d);
  }

  Widget _voiceSelectionCard(ColorScheme cs) {
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Voice selection',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            "Choose the voice used by your store's agent.",
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _voiceId != null && _voiceId!.isNotEmpty
                      ? _voiceId
                      : null,
                  decoration: const InputDecoration(labelText: 'Existing voices'),
                  items: _voiceOptions
                      .map((v) => DropdownMenuItem(
                            value: v.id,
                            child: Text(v.name.isEmpty ? v.id : v.name),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _voiceId = value;
                      _voiceName = _resolveVoiceName(value);
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              ShadButton.outline(
                onPressed: _voiceLoading ? null : _loadVoices,
                child: _voiceLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Refresh'),
              ),
            ],
          ),
          if (_voiceId != null && _voiceId!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Selected voice: ${_voiceName ?? _voiceId}',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ShadButton(
                onPressed: _voiceApplying ? null : _applySelectedVoice,
                child: _voiceApplying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Apply voice'),
              ),
              ShadButton.outline(
                onPressed: _voiceId == null ? null : _previewVoice,
                child: const Text('Preview'),
              ),
              if (_storeLoading) const Text('Loading current voice...'),
              if (_appliedVoiceId != null && _appliedVoiceId!.isNotEmpty)
                ShadBadge.secondary(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                      'Applied: ${_appliedVoiceName ?? _appliedVoiceId}'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _voiceUploadStep(ColorScheme cs, bool voiceReady) {
    return Column(
      key: const ValueKey('voice-upload'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            _TipTile(
              icon: Icons.headset_off,
              title: 'Avoid noisy environments',
              body: 'Background sounds interfere with recording quality results.',
            ),
            SizedBox(width: 16),
            _TipTile(
              icon: Icons.thumb_up_alt_outlined,
              title: 'Check microphone quality',
              body: 'Try external units or headphone mics for better capture.',
            ),
            SizedBox(width: 16),
            _TipTile(
              icon: Icons.mic_none,
              title: 'Use consistent equipment',
              body: "Don't change recording equipment between samples.",
            ),
          ],
        ),
        const SizedBox(height: 16),
        _DashedBorder(
          color: cs.outlineVariant,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: ShadButton.outline(
                    onPressed: _voiceCloneStep == 0
                        ? () => setState(() => _voiceCloneStep = 0)
                        : null,
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 160,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _recording
                          ? _RecordingStopButton(onPressed: _stopRecording)
                          : _AudioInputSelector(
                              inputs: _audioInputs,
                              selectedId: _selectedAudioInputId,
                              onChanged: (value) {
                                setState(() => _selectedAudioInputId = value);
                              },
                              onStart: _startRecording,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _WaveformBars(color: cs.onSurfaceVariant.withOpacity(0.6)),
                    const Spacer(),
                    _TimePill(
                      text:
                          '${_formatClock(_recordingElapsed)}  /  00:30',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ..._voiceSamples.asMap().entries.map((entry) {
          final index = entry.key;
          final sample = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sample.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        sample.duration != null
                            ? _formatDuration(sample.duration!)
                            : '',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => playAudioBytes(sample.upload.bytes),
                  icon: const Icon(Icons.play_arrow),
                ),
                IconButton(
                  onPressed: () => setState(() => _voiceSamples.removeAt(index)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          );
        }).toList(),
        const SizedBox(height: 4),
        Row(
          children: [
            ShadCheckbox(
              value: _voiceRemoveNoise,
              onChanged: (v) => setState(() => _voiceRemoveNoise = v),
            ),
            const SizedBox(width: 8),
            const Text('Remove background noise from audio recordings'),
          ],
        ),
        if (voiceReady) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 18),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ready',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    'Continue to add recordings for a better clone',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            _StatusDot(active: voiceReady),
            const SizedBox(width: 8),
            const Text('10 seconds of audio required'),
            const Spacer(),
            ShadButton(
              onPressed: voiceReady
                  ? () => setState(() => _voiceCloneStep = 1)
                  : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _voiceInfoStep(ColorScheme cs) {
    return Column(
      key: const ValueKey('voice-info'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.graphic_eq),
            ),
            const SizedBox(width: 12),
            ShadButton.outline(
              onPressed: _voiceId == null ? null : _previewVoice,
              child: const Text('Preview voice'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ShadInputFormField(
          controller: _voiceNameCtrl,
          label: const Text('Name'),
          placeholder: const Text('e.g. old British man'),
        ),
        const SizedBox(height: 12),
        Row(
          children: const [
            Expanded(
              child: Text('Label', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text('Value', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ..._voiceLabels.asMap().entries.map((entry) {
          final idx = entry.key;
          final row = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: row.labelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Label',
                      suffixIcon: Icon(Icons.expand_more),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: row.valueCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Value',
                      suffixIcon: Icon(Icons.expand_more),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _voiceLabels.removeAt(idx).dispose();
                    });
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          );
        }).toList(),
        ShadButton.outline(
          onPressed: () => setState(() => _voiceLabels.add(_VoiceLabelRow())),
          child: const Text('Add label'),
        ),
        const SizedBox(height: 12),
        ShadInputFormField(
          controller: _voiceDescriptionCtrl,
          label: const Text('Description'),
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _voiceConsent,
          onChanged: (v) => setState(() => _voiceConsent = v ?? false),
          title: const Text(
              'I confirm I have rights to use these audio samples and accept ElevenLabs policies.'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ShadButton.outline(
              onPressed: () => setState(() => _voiceCloneStep = 0),
              child: const Text('Back'),
            ),
            const Spacer(),
            ShadButton(
              onPressed: _voiceSaving ? null : _createVoice,
              child: _voiceSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save voice'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _voiceFinishStep(ColorScheme cs) {
    return Column(
      key: const ValueKey('voice-finish'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Try out your new clone',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Your voice is now ready to be used throughout the product.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _FinishCard(
          title: 'Generate speech',
          body: 'Take your new clone for a test drive with Text to Speech.',
          color: const Color(0xFFDCE6FF),
        ),
        const SizedBox(height: 12),
        _FinishCard(
          title: 'Speak with yourself',
          body: 'Speak with your own clone by creating an ElevenLabs Agent.',
          color: const Color(0xFFDCF5FF),
        ),
        const SizedBox(height: 12),
        _FinishCard(
          title: 'Narrate a story',
          body: 'Create a story narrated by you using Studio.',
          color: const Color(0xFFDFF6E8),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Spacer(),
            ShadButton(
              onPressed: () => setState(() => _voiceCloneStep = 0),
              child: const Text('Skip'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final voiceReady = _totalRecordedDuration().inSeconds >= 10;

    return BusinessScaffold(
      title: const Text('Agent voice'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Instant Voice Clone',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Create a custom voice for the store and apply it to the voice agent.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                _voiceSelectionCard(cs),
                const SizedBox(height: 12),
                ShadCard(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 220,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.flash_on_outlined, size: 28),
                            const SizedBox(height: 12),
                            const Text(
                              'Instant Voice Clone',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 16),
                            _VoiceStepItem(
                              label: 'Upload Audio',
                              active: _voiceCloneStep == 0,
                              done: _voiceCloneStep > 0,
                            ),
                            const SizedBox(height: 8),
                            _VoiceStepItem(
                              label: 'Voice Information',
                              active: _voiceCloneStep == 1,
                              done: _voiceCloneStep > 1,
                            ),
                            const SizedBox(height: 8),
                            _VoiceStepItem(
                              label: 'Finish up',
                              active: _voiceCloneStep == 2,
                              done: _voiceCloneStep > 2,
                            ),
                            const SizedBox(height: 16),
                            ShadButton.outline(
                              onPressed: () {},
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.chat_bubble_outline, size: 16),
                                  SizedBox(width: 6),
                                  Text('Feedback'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _voiceCloneStep == 0
                              ? _voiceUploadStep(cs, voiceReady)
                              : _voiceCloneStep == 1
                                  ? _voiceInfoStep(cs)
                                  : _voiceFinishStep(cs),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_voiceError != null) ...[
                  const SizedBox(height: 10),
                  ShadAlert.destructive(
                    title: const Text('Voice setup issue'),
                    description: Text(_voiceError!),
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

class _VoiceSample {
  _VoiceSample({
    required this.upload,
    required this.displayName,
    this.duration,
  });

  final VoiceSampleUpload upload;
  final String displayName;
  final Duration? duration;
}

class _VoiceLabelRow {
  _VoiceLabelRow({String label = '', String value = ''})
      : labelCtrl = TextEditingController(text: label),
        valueCtrl = TextEditingController(text: value);

  final TextEditingController labelCtrl;
  final TextEditingController valueCtrl;

  void dispose() {
    labelCtrl.dispose();
    valueCtrl.dispose();
  }
}

class _VoiceStepItem extends StatelessWidget {
  const _VoiceStepItem({
    required this.label,
    required this.active,
    required this.done,
  });

  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done || active ? Colors.green : cs.outlineVariant,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active
                ? null
                : cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AudioInputSelector extends StatelessWidget {
  const _AudioInputSelector({
    required this.inputs,
    required this.selectedId,
    required this.onChanged,
    required this.onStart,
  });

  final List<AudioInputDevice> inputs;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasInputs = inputs.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mic_none, size: 18),
              const SizedBox(width: 8),
              if (hasInputs)
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedId ?? inputs.first.id,
                    items: inputs
                        .map(
                          (device) => DropdownMenuItem(
                            value: device.id,
                            child: SizedBox(
                              width: 160,
                              child: Text(
                                device.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: onChanged,
                  ),
                )
              else
                const Text('Default microphone'),
            ],
          ),
        ),
        const SizedBox(width: 10),
        ShadButton(
          onPressed: onStart,
          child: const Text('Start'),
        ),
      ],
    );
  }
}

class _RecordingStopButton extends StatelessWidget {
  const _RecordingStopButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ShadButton.raw(
      variant: ShadButtonVariant.primary,
      onPressed: onPressed,
      padding: const EdgeInsets.all(18),
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      decoration: const ShadDecoration(shape: BoxShape.circle),
      child: const Icon(Icons.stop, size: 20),
    );
  }
}

class _TimePill extends StatelessWidget {
  const _TimePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? Colors.green : cs.outlineVariant,
      ),
    );
  }
}

class _WaveformBars extends StatelessWidget {
  const _WaveformBars({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    const heights = [6.0, 10.0, 8.0, 14.0, 9.0, 12.0, 7.0, 10.0];
    return Row(
      children: [
        for (final h in heights)
          Container(
            width: 3,
            height: h,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

class _TipTile extends StatelessWidget {
  const _TipTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: cs.onSurfaceVariant),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(body, style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _FinishCard extends StatelessWidget {
  const _FinishCard({
    required this.title,
    required this.body,
    required this.color,
  });

  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.play_arrow),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body,
                    style: TextStyle(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _DashedBorder extends StatelessWidget {
  const _DashedBorder({
    required this.child,
    required this.color,
    this.radius = 16,
    this.dashLength = 6,
    this.gapLength = 4,
    this.strokeWidth = 1.2,
  });

  final Widget child;
  final Color color;
  final double radius;
  final double dashLength;
  final double gapLength;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: color,
        radius: radius,
        dashLength: dashLength,
        gapLength: gapLength,
        strokeWidth: strokeWidth,
      ),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dashLength,
    required this.gapLength,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final double dashLength;
  final double gapLength;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashLength;
        final segment = metric.extractPath(distance, next);
        canvas.drawPath(segment, paint);
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.gapLength != gapLength ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
