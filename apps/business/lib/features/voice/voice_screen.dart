import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../providers/agent_customization_api.dart';
import '../../util/audio_player.dart';
import '../../util/audio_recorder.dart';
import '../../util/store_id.dart';
import '../../widgets/business_scaffold.dart';
import '../../widgets/shad_snackbar.dart';
import 'voice_helpers.dart';
import 'voice_models.dart';
import 'voice_selection_card.dart';
import 'voice_wizard_card.dart';

part 'voice_screen_actions.dart';
part 'voice_screen_body.dart';

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
  final List<VoiceSample> _voiceSamples = [];
  final List<VoiceLabelRow> _voiceLabels = [];
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
    _voiceLabels.add(VoiceLabelRow(label: 'Language', value: 'English'));
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recorder.dispose();
    _voiceNameCtrl.dispose();
    _voiceDescriptionCtrl.dispose();
    disposeVoiceLabelRows(_voiceLabels);
    super.dispose();
  }

  void _update(VoidCallback update) => setState(update);

  @override
  Widget build(BuildContext context) {
    return BusinessScaffold(
      title: const Text('Agent voice'),
      body: _buildBody(context),
    );
  }
}
