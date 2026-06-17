part of 'voice_screen.dart';

extension _VoiceScreenActions on _VoiceScreenState {
  Future<void> _loadStoreVoice() async {
    if (_storeLoading) return;
    _update(() {
      _storeLoading = true;
      _voiceError = null;
    });
    try {
      final api = AgentCustomizationApi();
      final data = await api.getStoreVoice(_storeId);
      final voiceId = (data['voice_id'] as String?)?.trim() ?? '';
      if (!mounted) return;
      _update(() {
        _appliedVoiceId = voiceId.isEmpty ? null : voiceId;
        _appliedVoiceName = voiceId.isEmpty ? null : _resolveVoiceName(voiceId);
        if ((_voiceId ?? '').isEmpty && voiceId.isNotEmpty) {
          _voiceId = voiceId;
          _voiceName = _appliedVoiceName;
          _voiceNameCtrl.text = _voiceName ?? '';
        }
      });
    } catch (error) {
      if (mounted) _update(() => _voiceError = error.toString());
    } finally {
      if (mounted) _update(() => _storeLoading = false);
    }
  }

  Future<void> _loadVoices() async {
    if (_voiceLoading) return;
    _update(() {
      _voiceLoading = true;
      _voiceError = null;
    });
    try {
      final api = AgentCustomizationApi();
      final voices = await api.listVoices();
      if (!mounted) return;
      _update(() {
        _voiceOptions = voices;
        if (_appliedVoiceId != null) {
          _appliedVoiceName = _resolveVoiceName(_appliedVoiceId!);
        }
        if (_voiceId != null) {
          _voiceName = _resolveVoiceName(_voiceId!);
        }
      });
    } catch (error) {
      if (mounted) _update(() => _voiceError = error.toString());
    } finally {
      if (mounted) _update(() => _voiceLoading = false);
    }
  }

  Future<void> _loadAudioInputs() async {
    try {
      final devices = await _recorder.listInputs();
      if (!mounted) return;
      _update(() {
        _audioInputs = devices;
        if (_selectedAudioInputId == null && devices.isNotEmpty) {
          _selectedAudioInputId = devices.first.id;
        }
      });
    } catch (_) {
      // Keep the recorder on the platform default input.
    }
  }

  Future<void> _startRecording() async {
    if (_recording) return;
    _update(() => _voiceError = null);
    try {
      await _recorder.start(deviceId: _selectedAudioInputId);
      if (!mounted) return;
      _update(() {
        _recording = true;
        _recordingElapsed = Duration.zero;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!_recording) {
          timer.cancel();
          return;
        }
        _update(() => _recordingElapsed += const Duration(seconds: 1));
        if (_recordingElapsed.inSeconds >= 30) {
          _stopRecording();
        }
      });
    } catch (error) {
      if (mounted) _update(() => _voiceError = error.toString());
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _recordingTimer?.cancel();
    try {
      final bytes = await _recorder.stop();
      if (!mounted) return;
      if (bytes.isEmpty) {
        _update(() => _recording = false);
        return;
      }
      final sample = createRecordedVoiceSample(
        index: _voiceSamples.length + 1,
        bytes: bytes,
        duration: _recordingElapsed,
      );
      _update(() {
        _voiceSamples.add(sample);
        _recording = false;
        _recordingElapsed = Duration.zero;
      });
    } catch (error) {
      if (!mounted) return;
      _update(() {
        _recording = false;
        _voiceError = error.toString();
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
    _update(() {
      _voiceApplying = true;
      _voiceError = null;
    });
    try {
      final api = AgentCustomizationApi();
      await api.setStoreVoice(storeId: _storeId, voiceId: voiceId);
      if (!mounted) return;
      _update(() {
        _appliedVoiceId = voiceId;
        _appliedVoiceName = _resolveVoiceName(voiceId);
      });
      showShadSnack(
        context,
        title: 'Voice applied',
        message: _appliedVoiceName,
        type: ShadSnackType.success,
      );
    } catch (error) {
      if (mounted) _update(() => _voiceError = error.toString());
    } finally {
      if (mounted) _update(() => _voiceApplying = false);
    }
  }

  Future<void> _createVoice() async {
    if (_voiceSaving) return;
    final name = _voiceNameCtrl.text.trim();
    final validationError = validateVoiceCreateInput(
      name: name,
      samples: _voiceSamples,
      consent: _voiceConsent,
    );
    if (validationError != null) {
      _update(() => _voiceError = validationError);
      return;
    }
    _update(() {
      _voiceSaving = true;
      _voiceError = null;
    });
    try {
      final labels = buildVoiceLabels(_voiceLabels);
      final api = AgentCustomizationApi();
      final voice = await api.createVoice(
        name: name,
        description: _voiceDescriptionCtrl.text.trim(),
        labels: labels.isEmpty ? null : labels,
        files: _voiceSamples.map((sample) => sample.upload).toList(),
        removeBackgroundNoise: _voiceRemoveNoise,
      );
      if (!mounted) return;
      await api.setStoreVoice(storeId: _storeId, voiceId: voice.id);
      _update(() {
        _voiceId = voice.id;
        _voiceName = voice.name;
        _appliedVoiceId = voice.id;
        _appliedVoiceName = voice.name;
        _voiceCloneStep = 2;
      });
      await _loadVoices();
    } catch (error) {
      if (mounted) _update(() => _voiceError = error.toString());
    } finally {
      if (mounted) _update(() => _voiceSaving = false);
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
    } catch (error) {
      if (mounted) _update(() => _voiceError = error.toString());
    }
  }

  String _resolveVoiceName(String voiceId) {
    return resolveVoiceName(_voiceOptions, voiceId);
  }
}
