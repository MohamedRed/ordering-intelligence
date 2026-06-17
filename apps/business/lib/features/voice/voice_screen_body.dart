part of 'voice_screen.dart';

extension _VoiceScreenBody on _VoiceScreenState {
  Widget _buildBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final voiceReady = hasMinimumVoiceSampleDuration(_voiceSamples);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: _VoiceScreenState._maxContentWidth,
          ),
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
              VoiceSelectionCard(
                voices: _voiceOptions,
                selectedVoiceId: _voiceId,
                selectedVoiceName: _voiceName,
                appliedVoiceId: _appliedVoiceId,
                appliedVoiceName: _appliedVoiceName,
                voiceLoading: _voiceLoading,
                voiceApplying: _voiceApplying,
                storeLoading: _storeLoading,
                onVoiceChanged: _selectVoice,
                onRefresh: _loadVoices,
                onApply: _applySelectedVoice,
                onPreview: _previewVoice,
              ),
              const SizedBox(height: 12),
              VoiceWizardCard(
                step: _voiceCloneStep,
                voiceReady: voiceReady,
                voiceId: _voiceId,
                voiceSaving: _voiceSaving,
                voiceNameController: _voiceNameCtrl,
                voiceDescriptionController: _voiceDescriptionCtrl,
                voiceLabels: _voiceLabels,
                voiceConsent: _voiceConsent,
                voiceRemoveNoise: _voiceRemoveNoise,
                recording: _recording,
                recordingElapsed: _recordingElapsed,
                audioInputs: _audioInputs,
                selectedAudioInputId: _selectedAudioInputId,
                samples: _voiceSamples,
                onStepChanged: _setVoiceCloneStep,
                onPreviewVoice: _previewVoice,
                onCreateVoice: _createVoice,
                onAddLabel: _addVoiceLabel,
                onRemoveLabel: _removeVoiceLabel,
                onConsentChanged: _setVoiceConsent,
                onRemoveNoiseChanged: _setVoiceRemoveNoise,
                onAudioInputChanged: _setAudioInput,
                onStartRecording: _startRecording,
                onStopRecording: _stopRecording,
                onPlaySample: _playSample,
                onRemoveSample: _removeSample,
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
    );
  }

  void _selectVoice(String voiceId) {
    _update(() {
      _voiceId = voiceId;
      _voiceName = _resolveVoiceName(voiceId);
    });
  }

  void _setVoiceCloneStep(int step) {
    _update(() => _voiceCloneStep = step);
  }

  void _addVoiceLabel() {
    _update(() => _voiceLabels.add(VoiceLabelRow()));
  }

  void _removeVoiceLabel(int index) {
    _update(() => _voiceLabels.removeAt(index).dispose());
  }

  void _setVoiceConsent(bool? value) {
    _update(() => _voiceConsent = value ?? false);
  }

  void _setVoiceRemoveNoise(bool value) {
    _update(() => _voiceRemoveNoise = value);
  }

  void _setAudioInput(String? value) {
    _update(() => _selectedAudioInputId = value);
  }

  void _playSample(VoiceSample sample) {
    playAudioBytes(sample.upload.bytes);
  }

  void _removeSample(int index) {
    _update(() => _voiceSamples.removeAt(index));
  }
}
