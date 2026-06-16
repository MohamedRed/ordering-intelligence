import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../providers/agent_customization_api.dart';
import '../../providers/tenant_providers.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/shad_snackbar.dart';
import '../../models/tenant.dart';
import '../../utils/audio_player.dart';
import '../../utils/audio_recorder.dart';
import 'flyer_attachment.dart';
import 'flyer_tile.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.tenantId, this.tenant});

  final String tenantId;
  final Tenant? tenant;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const int _stepMenu = 0;
  // Step 2: Optional voice clone / selection.
  static const int _stepVoice = 1;
  // Step 3: Fast (menu-only) ingestion.
  static const int _stepIngestion = 2;
  // Step 4: Optional image enrichment (resume the same jobId in full mode).
  static const int _stepImages = 3;
  static const int _stepAgent = 4;
  static const int _stepStripe = 5;
  static const int _stepFinalize = 6;
  static const int _stepCount = 7;

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl =
      TextEditingController(); // optional; may be filled by Stripe
  final _primaryCtrl =
      TextEditingController(); // optional; may be filled by Stripe
  final _storeIdCtrl = TextEditingController();
  final String _country = 'US';
  final _phoneCtrl =
      TextEditingController(); // optional; Stripe usually provides
  final _fuelPrepayCtrl = TextEditingController();
  final List<TextEditingController> _flyerCtrls = [];
  final List<FlyerAttachment> _flyers = [];
  String _businessType = 'fast_food';
  String _currencyCode = 'USD';
  bool _statusLoading = false;
  bool _finalizeLoading = false;
  bool _ingestTriggering = false;
  bool _ingestPolling = false;
  bool _ingestPollInFlight = false;
  bool _ingestCanceling = false;
  bool _ingestResumingImages = false;
  Timer? _ingestTimer;
  String? _ingestStatus;
  double? _ingestProgress; // 0..1
  String? _ingestStage;
  List<String> _ingestJobIds = const [];
  bool _fastIngestReady = false;
  bool _agentCreating = false;
  String? _agentId;
  String? _voiceId;
  String? _voiceName;
  bool _voiceApplied = false;
  bool _voiceLoading = false;
  bool _voiceSaving = false;
  String? _voiceError;
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
  List<ElevenLabsVoice> _voiceOptions = const [];
  bool _publishingMenu = false;
  bool _menuPublished = false;
  String? _menuPublishedJobId;
  bool _verifyingMenuSnapshot = false;
  int? _menuSnapshotItemCount;
  DateTime? _menuSnapshotCheckedAt;
  bool _stepSaving = false;
  int _step = 0;
  String? _sessionId;
  String? _error;
  String? _stripeAccountId;
  bool _initialLoadDone = false;
  bool _resumeLoading = true;
  bool _workflowVisible = false;
  bool _workflowLoading = false;
  bool _workflowPollInFlight = false;
  DateTime? _workflowLastFetch;
  String? _workflowJobId;
  List<_WorkflowTraceNode> _workflowNodes = const [];
  String? _workflowSelectedId;
  String? _workflowHoveredId;
  static const _menuFlyerBucket = 'ordering-intelligence-menus-dev';
  static const _demoSkipStripeFlag = 'demo_skip_stripe';
  _Step1Snapshot? _step1Baseline;

  static const _maxContentWidth = 720.0;

  bool get _demoSkipStripe =>
      widget.tenant?.featureFlags[_demoSkipStripeFlag] ?? false;

  static const List<_IngestStageSpec> _ingestStageSpecs = [
    _IngestStageSpec(key: 'queued', label: 'Queued', icon: Icons.schedule),
    _IngestStageSpec(
        key: 'analyze', label: 'Analyze', icon: Icons.text_snippet_outlined),
    _IngestStageSpec(
        key: 'composites', label: 'Composites', icon: Icons.grid_view_outlined),
    _IngestStageSpec(key: 'extract', label: 'Extract', icon: Icons.crop),
    _IngestStageSpec(key: 'assign', label: 'Assign', icon: Icons.link),
    _IngestStageSpec(key: 'write', label: 'Write', icon: Icons.save_outlined),
    _IngestStageSpec(
        key: 'done', label: 'Done', icon: Icons.check_circle_outline),
    _IngestStageSpec(
        key: 'canceled', label: 'Canceled', icon: Icons.stop_circle_outlined),
    _IngestStageSpec(key: 'error', label: 'Error', icon: Icons.error_outline),
  ];

  String _normalizedIngestStage({
    required String status,
    required String? stage,
  }) {
    final s = status.toLowerCase();
    if (s == 'succeeded' || s == 'partial_ok' || s == 'ready') return 'done';
    if (s == 'canceled') return 'canceled';
    if (s == 'error' || s == 'failed') return 'error';
    final st = (stage ?? '').toLowerCase();
    if (st.isEmpty) {
      return s == 'processing'
          ? 'analyze'
          : (s == 'queued' ? 'queued' : 'queued');
    }
    if (st == 'processing') return 'analyze';
    if (st == 'completed') return 'done';
    return st;
  }

  Widget _ingestStageViz({
    required String status,
    required String? stage,
    required double? progress,
  }) {
    final cs = Theme.of(context).colorScheme;
    final key = _normalizedIngestStage(status: status, stage: stage);
    final idx = _ingestStageSpecs.indexWhere((s) => s.key == key);
    final current = idx >= 0 ? idx : 0;
    final isError = _ingestStageSpecs[current].key == 'error';
    final isCanceled = _ingestStageSpecs[current].key == 'canceled';

    Color nodeColor(int i) {
      if (i < current) return Colors.green;
      if (i == current) {
        if (isError) return cs.error;
        if (isCanceled) return cs.tertiary;
        return ShadTheme.of(context).colorScheme.primary;
      }
      return cs.outlineVariant;
    }

    Color lineColor(int i) => i < current ? Colors.green : cs.outlineVariant;

    Widget node(int i) {
      final spec = _ingestStageSpecs[i];
      final active = i == current;
      final done = i < current;
      final color = nodeColor(i);
      final icon = done
          ? Icons.check
          : active &&
                  (spec.key == 'queued' ||
                      spec.key == 'analyze' ||
                      spec.key == 'composites' ||
                      spec.key == 'extract' ||
                      spec.key == 'assign' ||
                      spec.key == 'write')
              ? null
              : spec.icon;

      final child = icon == null
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 16, color: Colors.white);

      return SizedBox(
        width: 92,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: child,
            ),
            const SizedBox(height: 6),
            Text(
              spec.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ShadCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Pipeline',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (progress != null)
                ShadBadge.secondary(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('${(progress * 100).round()}%'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(_ingestStageSpecs.length, (i) {
                final parts = <Widget>[node(i)];
                if (i != _ingestStageSpecs.length - 1) {
                  parts.add(
                    Container(
                      margin: const EdgeInsets.only(top: 14),
                      width: 26,
                      height: 2,
                      color: lineColor(i),
                    ),
                  );
                }
                return Row(children: parts);
              }),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final t = widget.tenant;
    if (t != null) {
      _nameCtrl.text = t.name;
      _primaryCtrl.text = t.primaryUser;
      _storeIdCtrl.text = t.storeId;
      if (t.businessType.isNotEmpty) {
        _businessType = t.businessType;
      }
      if (t.phone.isNotEmpty) {
        _phoneCtrl.text = t.phone;
      }
      if (t.timezone.isNotEmpty) {
        // We no longer expose timezone override in UI, but keep it for display.
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadResumeState());
  }

  Future<void> _loadResumeState() async {
    if (_initialLoadDone) return;
    _initialLoadDone = true;
    final tenantId = widget.tenantId.trim();
    if (tenantId.isEmpty) {
      if (mounted) setState(() => _resumeLoading = false);
      return;
    }
    try {
      final api = ref.read(tenantApiProvider);
      final data = await api.tenantOnboarding(tenantId);
      final session = data['session'] as Map<String, dynamic>?;
      if (session == null) return;

      final sessionId = session['session_id'] as String?;
      if (sessionId == null || sessionId.isEmpty) return;

      final flyers = (session['flyers'] as List<dynamic>?)?.cast<String>() ??
          const <String>[];
      final stripe = session['stripe'] as Map<String, dynamic>?;
      final stripeAccountId = stripe?['account_id'] as String?;
      final status = session['status'] as String? ?? '';
      final ingestion = session['ingestion'] as Map<String, dynamic>?;
      final jobIds =
          (ingestion?['job_ids'] as List<dynamic>?)?.cast<String>() ??
              const <String>[];
      final ingestStatus = ingestion?['status'] as String?;
      final fastReadyRaw = ingestion?['fast_ready'];
      final fastReady = fastReadyRaw is bool ? fastReadyRaw : false;
      final done = ['succeeded', 'partial_ok']
          .contains((ingestStatus ?? '').toLowerCase());
      final fastReadyEffective = fastReady || done;
      final agent = session['agent'] as Map<String, dynamic>?;
      final agentId = agent?['agent_id'] as String?;
      final voiceId = agent?['voice_id'] as String?;
      final voiceName = agent?['voice_name'] as String?;
      final branchId = agent?['branch_id'] as String?;
      final business = session['business'] as Map<String, dynamic>?;
      final businessCurrency = (business?['currency'] ??
              business?['currency_type'] ??
              business?['currencyType'] ??
              '')
          .toString()
          .trim();
      final fuelDefaultCents = _anyToInt(
          business?['fuel_default_prepay_cents'] ??
              business?['fuel_prepay_default_cents'] ??
              business?['fuelDefaultPrepayCents']);
      var resumeStep = _stepMenu;

      setState(() {
        _sessionId = sessionId;
        _stripeAccountId = stripeAccountId;
        _ingestJobIds = jobIds;
        _ingestStatus = ingestStatus;
        _fastIngestReady = fastReadyEffective;
        _agentId = agentId;
        _voiceId = voiceId;
        _voiceName = voiceName;
        _voiceApplied = branchId != null && branchId.isNotEmpty;
        if (voiceName != null && voiceName.isNotEmpty) {
          _voiceNameCtrl.text = voiceName;
        }
        if (businessCurrency.isNotEmpty) {
          _currencyCode = businessCurrency.toUpperCase();
        }
        if (fuelDefaultCents > 0) {
          _fuelPrepayCtrl.text = _formatCents(fuelDefaultCents);
        }

        // Hydrate flyers as tiles (network thumbnails when possible).
        if (flyers.isNotEmpty && _flyers.isEmpty) {
          for (final url in flyers) {
            final key = _extractGcsKey(url);
            final mime = _guessMimeFromUrl(url);
            final att = FlyerAttachment(
              name: _filenameFromUrl(url),
              bytes: null,
              mime: mime,
            )
              ..uploadedUrl = url
              ..uploadedKey = key;
            _flyers.add(att);
          }
        }

        // Baseline for change detection in step 1.
        _step1Baseline = _Step1Snapshot(
          storeId: _storeIdCtrl.text.trim(),
          businessType: _businessType,
          country: _country,
          flyerUrls: _currentFlyerUrls(),
          currency: _currencyCode,
          fuelDefaultPrepayCents: _parseCurrencyCents(_fuelPrepayCtrl.text),
        );

        // Resume step (demo-friendly ordering):
        // - ready => finalize
        // - fast ingestion started => ingestion
        // - image enrichment running => images
        // - fast ingestion complete => agent (or stripe/finalize if already created)
        // - flyers exist => ingestion
        if (status == 'ready') {
          resumeStep = _stepFinalize;
        } else if (jobIds.isNotEmpty ||
            status == 'ingesting' ||
            ingestStatus != null) {
          if (!fastReadyEffective) {
            resumeStep = _stepIngestion;
          } else if (!done) {
            // Job is running, but we already have a fast draft: treat this as image enrichment.
            resumeStep = _stepImages;
          } else if (agentId != null && agentId.isNotEmpty) {
            // If agent is already created, proceed to Stripe (or finalize if Stripe is already ready/skipped).
            resumeStep = _step2Valid() ? _stepFinalize : _stepStripe;
          } else {
            resumeStep = _stepAgent;
          }
        } else if (flyers.isNotEmpty) {
          resumeStep = _stepIngestion;
        } else {
          resumeStep = _stepMenu;
        }
        _step = resumeStep;
      });
      if (!mounted) return;
      if (resumeStep == _stepIngestion || resumeStep == _stepImages) {
        _startIngestPolling();
      }
      if (resumeStep == _stepAgent && (agentId == null || agentId.isEmpty)) {
        _createAgent(auto: true);
      }
    } catch (_) {
      // Best-effort resume; ignore failures here and let user proceed.
    } finally {
      if (mounted) setState(() => _resumeLoading = false);
    }
  }

  String _filenameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.isEmpty) return 'flyer';
      return uri.pathSegments.last.isNotEmpty ? uri.pathSegments.last : 'flyer';
    } catch (_) {
      return 'flyer';
    }
  }

  String _guessMimeFromUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    // Signed URLs often omit the filename extension; assume image for menu-flyer keys.
    if (lower.contains('/menu-flyers/')) return 'image/jpeg';
    return 'application/octet-stream';
  }

  String? _extractGcsKey(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    // https://storage.googleapis.com/<bucket>/<key>
    if (uri.host == 'storage.googleapis.com') {
      if (uri.pathSegments.length >= 2 &&
          uri.pathSegments.first == _menuFlyerBucket) {
        return uri.pathSegments.skip(1).join('/');
      }
    }
    // https://<bucket>.storage.googleapis.com/<key>
    if (uri.host.endsWith('.storage.googleapis.com')) {
      final bucket = uri.host.split('.').first;
      if (bucket == _menuFlyerBucket) {
        final key = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
        return key.isEmpty ? null : key;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _ingestTimer?.cancel();
    _recordingTimer?.cancel();
    _recorder.dispose();
    _nameCtrl.dispose();
    _primaryCtrl.dispose();
    _storeIdCtrl.dispose();
    _phoneCtrl.dispose();
    _fuelPrepayCtrl.dispose();
    _voiceNameCtrl.dispose();
    _voiceDescriptionCtrl.dispose();
    for (final row in _voiceLabels) {
      row.dispose();
    }
    for (final c in _flyerCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _triggerIngestion() async {
    final urls = _currentFlyerUrls();
    if (urls.isEmpty) {
      showShadSnack(
        context,
        title: 'Add flyers first',
        message:
            'Upload at least one menu page/flyer before starting ingestion.',
        type: ShadSnackType.warning,
      );
      _setStep(_stepMenu);
      return;
    }
    setState(() {
      _ingestTriggering = true;
      _error = null;
      _fastIngestReady = false;
      _ingestStage = null;
      _ingestProgress = null;
    });
    try {
      final api = ref.read(tenantApiProvider);
      final sessionId = await _ensureSession(api);
      await _attachFlyers(api, sessionId);

      final jobId = await api.triggerIngest(sessionId, mode: 'menu_only');
      if (jobId != null && jobId.isNotEmpty) {
        setState(() {
          if (!_ingestJobIds.contains(jobId)) {
            _ingestJobIds = [..._ingestJobIds, jobId];
          }
          // New ingestion run => publishing needs to be re-done for the latest job.
          _menuPublished = false;
          _menuPublishedJobId = null;
        });
      }

      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Ingestion started',
        message: jobId != null ? 'Job: $jobId' : null,
        type: ShadSnackType.success,
      );
      _startIngestPolling();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _ingestTriggering = false);
    }
  }

  String? _latestIngestJobId() {
    if (_ingestJobIds.isEmpty) return null;
    return _ingestJobIds.last;
  }

  Future<void> _resumeImageEnrichment() async {
    if (_ingestResumingImages) return;
    final urls = _currentFlyerUrls();
    if (urls.isEmpty) {
      showShadSnack(
        context,
        title: 'Add flyers first',
        message: 'Upload at least one menu page/flyer before enriching images.',
        type: ShadSnackType.warning,
      );
      _setStep(_stepMenu);
      return;
    }
    setState(() {
      _ingestResumingImages = true;
      _error = null;
      _ingestStage = null;
      _ingestProgress = null;
    });
    try {
      final api = ref.read(tenantApiProvider);
      final sessionId = await _ensureSession(api);
      await _attachFlyers(api, sessionId);

      final jobId = await api.resumeIngestImages(sessionId);
      if (jobId != null && jobId.isNotEmpty) {
        setState(() {
          if (!_ingestJobIds.contains(jobId)) {
            _ingestJobIds = [..._ingestJobIds, jobId];
          }
        });
      }

      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Image enrichment started',
        message: jobId != null ? 'Job: $jobId' : null,
        type: ShadSnackType.success,
      );
      _startIngestPolling();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _ingestResumingImages = false);
    }
  }

  Future<void> _publishMenuToAgent() async {
    final jobId = _latestIngestJobId();
    if (jobId == null || jobId.isEmpty) return;
    setState(() {
      _publishingMenu = true;
      _error = null;
    });
    try {
      await ref.read(tenantApiProvider).approveIngestJob(jobId);
      if (!mounted) return;
      setState(() {
        _menuPublished = true;
        _menuPublishedJobId = jobId;
      });
      showShadSnack(
        context,
        title: 'Menu published',
        message:
            'The agent can now read the menu snapshot for store ${_storeIdCtrl.text.trim()}.',
        type: ShadSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      showShadSnack(
        context,
        title: 'Publish failed',
        message: '$e',
        type: ShadSnackType.error,
      );
    } finally {
      if (mounted) setState(() => _publishingMenu = false);
    }
  }

  Future<void> _verifyAgentMenuSnapshot() async {
    final storeId = _storeIdCtrl.text.trim();
    if (storeId.isEmpty) return;
    setState(() {
      _verifyingMenuSnapshot = true;
      _error = null;
    });
    try {
      final snap = await ref
          .read(tenantApiProvider)
          .getOrderServiceMenuSnapshot(storeId: storeId);
      if (!mounted) return;
      if (snap == null) {
        setState(() {
          _menuSnapshotItemCount = null;
          _menuSnapshotCheckedAt = DateTime.now();
        });
        showShadSnack(
          context,
          title: 'Menu snapshot not found',
          message: 'Publish the menu first, then verify again.',
          type: ShadSnackType.warning,
        );
        return;
      }
      final items = (snap['items'] as List?) ?? const [];
      setState(() {
        _menuSnapshotItemCount = items.length;
        _menuSnapshotCheckedAt = DateTime.now();
      });
      showShadSnack(
        context,
        title: 'Menu snapshot OK',
        message: 'Agent will see ${items.length} items.',
        type: ShadSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      showShadSnack(
        context,
        title: 'Snapshot verify failed',
        message: '$e',
        type: ShadSnackType.error,
      );
    } finally {
      if (mounted) setState(() => _verifyingMenuSnapshot = false);
    }
  }

  Future<void> _cancelIngestion() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    setState(() {
      _ingestCanceling = true;
      _error = null;
    });
    try {
      final api = ref.read(tenantApiProvider);
      await api.cancelIngest(sessionId);
      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Ingestion canceled',
        message: 'Job(s): ${_ingestJobIds.length}',
        type: ShadSnackType.info,
      );
      await _pollIngestOnce();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _ingestCanceling = false);
    }
  }

  Future<void> _createAgent({required bool auto}) async {
    if (_agentCreating) return;
    setState(() {
      _agentCreating = true;
      _error = null;
    });
    try {
      final api = ref.read(tenantApiProvider);
      final sessionId = await _ensureSession(api);
      final agentId = await api.createAgent(sessionId);
      if (!mounted) return;
      setState(() => _agentId = agentId);
      await _applyVoiceIfNeeded(sessionId);
      if (!mounted) return;
      if (!auto) {
        showShadSnack(
          context,
          title: 'Agent configured',
          message: agentId,
          type: ShadSnackType.success,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      if (!auto) {
        showShadSnack(
          context,
          title: 'Agent setup failed',
          message: e.toString(),
          type: ShadSnackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _agentCreating = false);
    }
  }

  Future<void> _applyVoiceIfNeeded(String sessionId) async {
    final voiceId = _voiceId?.trim() ?? '';
    if (voiceId.isEmpty || _voiceApplied || _voiceSaving) return;
    setState(() {
      _voiceSaving = true;
      _voiceError = null;
    });
    try {
      final api = AgentCustomizationApi();
      await api.applySessionVoice(sessionId: sessionId, voiceId: voiceId);
      if (!mounted) return;
      setState(() {
        _voiceApplied = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiceError = e.toString());
    } finally {
      if (mounted) setState(() => _voiceSaving = false);
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
      setState(() => _voiceOptions = voices);
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
      // Ignore failures; fallback to default device.
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
    setState(() {
      _voiceError = null;
    });
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

  Future<void> _saveSelectedVoice(String voiceId) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    setState(() {
      _voiceSaving = true;
      _voiceError = null;
    });
    try {
      final api = AgentCustomizationApi();
      final name = _voiceOptions
          .firstWhere((v) => v.id == voiceId,
              orElse: () => ElevenLabsVoice(id: voiceId, name: voiceId))
          .name;
      await api.setSessionVoice(
          sessionId: sessionId, voiceId: voiceId, voiceName: name);
      if (!mounted) return;
      setState(() {
        _voiceId = voiceId;
        _voiceName = name;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiceError = e.toString());
    } finally {
      if (mounted) setState(() => _voiceSaving = false);
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
      final sessionId = _sessionId;
      if (sessionId != null && voice.id.isNotEmpty) {
        await api.setSessionVoice(
          sessionId: sessionId,
          voiceId: voice.id,
          voiceName: voice.name,
        );
      }
      setState(() {
        _voiceId = voice.id;
        _voiceName = voice.name;
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

  Future<void> _pollIngestOnce() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    if (_ingestPollInFlight) return;
    _ingestPollInFlight = true;
    try {
      final api = ref.read(tenantApiProvider);
      final status = await api.status(sessionId);
      final ingestion = status['ingestion'] as Map<String, dynamic>?;
      final jobIds =
          (ingestion?['job_ids'] as List<dynamic>?)?.cast<String>() ??
              const <String>[];
      final ingestStatus = ingestion?['status'] as String?;
      final fastReadyRaw = ingestion?['fast_ready'];
      final fastReadyFromSession = fastReadyRaw is bool ? fastReadyRaw : false;
      final agent = status['agent'] as Map<String, dynamic>?;
      final agentId = agent?['agent_id'] as String?;
      if (!mounted) return;
      setState(() {
        _ingestJobIds = jobIds;
        _ingestStatus =
            ingestStatus ?? (jobIds.isEmpty ? 'not_started' : _ingestStatus);
        _fastIngestReady = _fastIngestReady ||
            fastReadyFromSession ||
            ['succeeded', 'partial_ok']
                .contains((ingestStatus ?? '').toLowerCase());
        if (agentId != null && agentId.isNotEmpty) {
          _agentId = agentId;
        }
      });

      // If we don't have job IDs yet, avoid calling sync-ingest (it will 400).
      if (jobIds.isNotEmpty) {
        try {
          // Prefer server-side sync (reads the menus_ingest docs and updates session.ingestion).
          final sync = await api.syncIngest(sessionId);
          final synced = sync['status'] as String?;
          final fastReadySyncRaw = sync['fast_ready'];
          final fastReadyFromSync =
              fastReadySyncRaw is bool ? fastReadySyncRaw : false;
          final progress = sync['progress'] as Map<String, dynamic>?;
          final pct = progress?['percent'];
          final stage = progress?['stage'];
          if (!mounted) return;
          setState(() {
            _ingestStatus = synced ?? _ingestStatus;
            _fastIngestReady = _fastIngestReady ||
                fastReadyFromSync ||
                ['succeeded', 'partial_ok']
                    .contains(((synced ?? '')).toLowerCase());
            if (pct is num) {
              _ingestProgress = (pct.clamp(0, 100) / 100.0).toDouble();
            }
            if (stage is String) {
              _ingestStage = stage;
            }
          });
        } catch (_) {
          // Ignore transient sync errors.
        }
      }

      if (_workflowVisible && jobIds.isNotEmpty) {
        await _pollWorkflowOnce();
      }
    } catch (_) {
      // Ignore transient polling errors.
    } finally {
      _ingestPollInFlight = false;
    }
  }

  Future<void> _pollWorkflowOnce({bool force = false}) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    if (!_workflowVisible) return;
    if (_workflowPollInFlight) return;

    final now = DateTime.now();
    final last = _workflowLastFetch;
    if (!force && last != null && now.difference(last).inMilliseconds < 4000) {
      return;
    }

    _workflowPollInFlight = true;
    if (mounted && _workflowNodes.isEmpty) {
      setState(() => _workflowLoading = true);
    }
    try {
      final api = ref.read(tenantApiProvider);
      final resp = await api.ingestWorkflow(sessionId, limit: 1200);
      final nodesRaw = resp['nodes'] as List<dynamic>? ?? const [];
      final jobId = resp['job_id'] as String?;

      final nodes = <_WorkflowTraceNode>[];
      for (final n in nodesRaw) {
        if (n is Map<String, dynamic>) {
          nodes.add(_WorkflowTraceNode.fromJson(n));
        } else if (n is Map) {
          nodes.add(_WorkflowTraceNode.fromJson(n.cast<String, dynamic>()));
        }
      }
      nodes.sort((a, b) => a.seq.compareTo(b.seq));

      if (!mounted) return;
      setState(() {
        _workflowJobId = jobId;
        _workflowNodes = nodes;
      });
    } catch (_) {
      // Best-effort; ignore transient workflow fetch errors.
    } finally {
      _workflowLastFetch = DateTime.now();
      _workflowPollInFlight = false;
      if (mounted) setState(() => _workflowLoading = false);
    }
  }

  _WorkflowTraceNode? _activeWorkflowNode() {
    if (_workflowNodes.isEmpty) return null;
    final id = _workflowSelectedId ?? _workflowHoveredId;
    if (id == null) return null;
    return _workflowNodes
        .where((n) => n.id == id)
        .cast<_WorkflowTraceNode?>()
        .firstWhere((n) => n != null, orElse: () => null);
  }

  void _selectWorkflowNode(String? id) {
    setState(() => _workflowSelectedId = id);
  }

  Future<void> _showImagePreview(String url) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: SizedBox(
            width: MediaQuery.of(ctx).size.width * 0.92,
            height: MediaQuery.of(ctx).size.height * 0.92,
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Preview',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    ShadButton.ghost(
                      size: ShadButtonSize.sm,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: url));
                      },
                      child: const Text('Copy URL'),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.4,
                    maxScale: 4.0,
                    child: Center(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stack) => Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text('Image failed to load: $error'),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openWorkflowFullscreen() async {
    final sessionId = _sessionId;
    if (sessionId == null) {
      showShadSnack(
        context,
        title: 'No session',
        message: 'Start onboarding first to view workflow.',
        type: ShadSnackType.warning,
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog.fullscreen(
          child: _WorkflowFullscreenDialog(
            sessionId: sessionId,
            initialNodes: _workflowNodes,
            initialJobId: _workflowJobId,
          ),
        );
      },
    );
  }

  void _startIngestPolling() {
    if (_ingestPolling) return;
    _ingestPolling = true;
    _ingestTimer?.cancel();
    _pollIngestOnce();
    _ingestTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await _pollIngestOnce();
      // Stop polling once we reach a terminal state.
      final s = _ingestStatus ?? '';
      if (['succeeded', 'partial_ok', 'error', 'failed', 'canceled']
          .contains(s)) {
        _stopIngestPolling();
      }
    });
    if (mounted) setState(() {});
  }

  void _stopIngestPolling() {
    _ingestTimer?.cancel();
    _ingestTimer = null;
    _ingestPolling = false;
    if (mounted) setState(() {});
  }

  Future<void> _checkStatus() async {
    setState(() {
      _statusLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(tenantApiProvider);
      final sessionId = await _ensureSession(api);
      final status = await api.status(sessionId);
      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Status',
        message:
            'Session=${status['status']} • Ingest=${status['ingestion']?['status']} • Stripe=${status['stripe']?['status'] ?? status['stripe']} • Agent=${status['agent']?['agent_id'] ?? '-'}',
        type: ShadSnackType.info,
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _statusLoading = false);
    }
  }

  Future<void> _finalize() async {
    setState(() {
      _finalizeLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(tenantApiProvider);
      final sessionId = await _ensureSession(api);
      await _attachFlyers(api, sessionId);
      await api.finalize(sessionId);
      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Onboarding finalized',
        message: 'Session: $sessionId',
        type: ShadSnackType.success,
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _finalizeLoading = false);
    }
  }

  bool _step1Valid() =>
      _storeIdCtrl.text.trim().isNotEmpty && _currentFlyerUrls().isNotEmpty;
  bool _step2Valid() => _demoSkipStripe || _stripeAccountId != null;
  bool _step3Valid() => _fastIngestReady;
  bool _step4Valid() => (_agentId ?? '').trim().isNotEmpty;

  _Step1Snapshot _currentStep1Snapshot() => _Step1Snapshot(
        storeId: _storeIdCtrl.text.trim(),
        businessType: _businessType,
        country: _country,
        flyerUrls: _currentFlyerUrls(),
        currency: _currencyCode,
        fuelDefaultPrepayCents: _parseCurrencyCents(_fuelPrepayCtrl.text),
      );

  int _anyToInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _parseCurrencyCents(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null || value.isNaN || value <= 0) return 0;
    return (value * 100).round();
  }

  String _formatCents(int cents) => (cents / 100).toStringAsFixed(2);

  Future<void> _nextStep() async {
    if (_step == _stepMenu && !_step1Valid()) {
      showShadSnack(context,
          title: 'Add flyers and store slug',
          message: 'At least one flyer/URL and a store slug are required.');
      return;
    }
    // Step 2 is FastIngestion (menu-only). Require it before continuing.
    if (_step == _stepIngestion && !_step3Valid()) {
      showShadSnack(
        context,
        title: 'Ingestion in progress',
        message:
            'Wait until the fast menu ingestion completes before continuing.',
        type: ShadSnackType.info,
      );
      return;
    }
    if (_step == _stepAgent && !_step4Valid()) {
      showShadSnack(
        context,
        title: 'Agent not created',
        message: 'Create the ElevenLabs agent before continuing.',
        type: ShadSnackType.info,
      );
      return;
    }
    if (_step == _stepStripe && !_step2Valid()) {
      showShadSnack(context,
          title: 'Stripe not ready',
          message: 'Create the Stripe account before continuing.');
      return;
    }
    if (_step == _stepMenu) {
      // Persist step 1 data (session, flyers, slug, business type)
      if (!_formKey.currentState!.validate()) return;
      setState(() {
        _stepSaving = true;
        _error = null;
      });
      try {
        final api = ref.read(tenantApiProvider);
        final current = _currentStep1Snapshot();

        // No changes since last resume/save: just continue.
        if (_sessionId != null &&
            _step1Baseline != null &&
            current == _step1Baseline) {
          _setStep(_stepVoice);
          return;
        }

        final sessionId = await _ensureSession(api);

        final before = _step1Baseline ?? _Step1Snapshot.empty();
        final beforeSet = before.flyerUrls.toSet();
        final afterSet = current.flyerUrls.toSet();
        final removed = beforeSet.difference(afterSet).toList();
        final added = afterSet.difference(beforeSet).toList();

        if (removed.isNotEmpty) {
          await api.detachFlyers(sessionId, removed);
        }
        if (added.isNotEmpty) {
          await api.attachFlyers(sessionId, added);
        }

        final businessChanged = _step1Baseline == null ||
            before.storeId != current.storeId ||
            before.businessType != current.businessType ||
            before.country != current.country;
        if (businessChanged) {
          final fuelDefaultPrepayCents =
              _parseCurrencyCents(_fuelPrepayCtrl.text);
          await api.updateBusiness(
            sessionId: sessionId,
            name: _nameCtrl.text.trim(),
            primaryUser: _primaryCtrl.text.trim(),
            storeId: _storeIdCtrl.text.trim(),
            businessType: _businessType,
            timezone: null,
            country: _country,
            phone: _phoneCtrl.text.trim(),
            currency: _currencyCode,
            fuelDefaultPrepayCents: fuelDefaultPrepayCents,
          );
        }

        _step1Baseline = current;
        _setStep(_stepVoice);
      } catch (e) {
        setState(() => _error = e.toString());
      } finally {
        setState(() => _stepSaving = false);
      }
      return;
    }

    _setStep((_step + 1).clamp(0, _stepFinalize));
  }

  void _prevStep() => _setStep((_step - 1).clamp(0, _stepFinalize));

  void _setStep(int next) {
    setState(() => _step = next);
    // Ingest steps (Fast + Images) need polling.
    if (next == _stepIngestion || next == _stepImages) {
      _startIngestPolling();
    } else {
      _stopIngestPolling();
    }
    if (next == _stepVoice) {
      _loadVoices();
      _loadAudioInputs();
      if (_voiceLabels.isEmpty) {
        _voiceLabels.add(_VoiceLabelRow(label: 'Language', value: 'English'));
      }
    }
    // Agent step: auto-create if missing (idempotent server-side).
    if (next == _stepAgent && !_step4Valid() && !_agentCreating) {
      // Fire and forget; UI shows local loading state.
      _createAgent(auto: true);
    }
    // Stripe step: auto-create account if missing (unless demo mode skips Stripe).
    if (next == _stepStripe &&
        !_demoSkipStripe &&
        !_step2Valid() &&
        !_statusLoading) {
      _startStripeOnboarding();
    }
  }

  Future<void> _startStripeOnboarding() async {
    if (_stripeAccountId != null) return; // already created
    setState(() {
      _statusLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(tenantApiProvider);
      final sessionId = await _ensureSession(api);
      // Stripe business_type must be one of: individual | company | non_profit | government_entity.
      // We always use company; our store type is tracked separately.
      final acct =
          await api.createStripeAccount(sessionId, businessType: 'company');
      setState(() {
        _stripeAccountId = acct;
      });
      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Stripe account created',
        message: acct,
        type: ShadSnackType.success,
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _statusLoading = false);
    }
  }

  Widget _stepperControls() {
    return Row(
      children: [
        if (_step > 0)
          ShadButton.outline(onPressed: _prevStep, child: const Text('Back')),
        const Spacer(),
        if (_step < _stepFinalize)
          ShadButton(
            onPressed: _stepSaving ? null : _nextStep,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_stepSaving) ...[
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(_stepSaving ? 'Saving…' : 'Next'),
              ],
            ),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }

  Widget _stepIndicator() {
    // Demo-ready after Step 2 (FastIngestion). Image enrichment is optional.
    final labels = [
      'Menu',
      'Voice',
      'Fast ingestion',
      'Image enrichment',
      'Agent',
      'Stripe',
      'Finalize'
    ];
    return ShadCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Wrap(
        spacing: 18,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: List.generate(_stepCount, (i) {
          final active = i == _step;
          final done = i < _step;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: done
                    ? Colors.green
                    : active
                        ? ShadTheme.of(context).colorScheme.primary
                        : Colors.grey[400],
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                labels[i],
                style: TextStyle(
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active
                      ? null
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _step1() {
    final tenant = widget.tenant;
    final storeLocked = tenant != null && tenant.storeId.isNotEmpty;
    final typeLocked = tenant != null && tenant.businessType.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tenant != null) ...[
          ShadCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.business_outlined, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tenant.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ID: ${tenant.id} • Store: ${tenant.storeId}',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        ShadCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Menu pages / flyers',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  ShadBadge.secondary(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: const Text('Required'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Upload images/PDFs (preferred) or paste public URLs.',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ..._flyers.asMap().entries.map((entry) => FlyerTile(
                        flyer: entry.value,
                        onRemove: () async {
                          final f = entry.value;
                          final sessionId = _sessionId;
                          setState(() {
                            _flyers.removeAt(entry.key);
                          });
                          if (sessionId != null && f.uploadedUrl != null) {
                            try {
                              await ref
                                  .read(tenantApiProvider)
                                  .detachFlyers(sessionId, [f.uploadedUrl!]);
                              _step1Baseline = _currentStep1Snapshot();
                            } catch (_) {}
                          }
                          if (f.uploadedKey != null) {
                            try {
                              await ref
                                  .read(tenantApiProvider)
                                  .deleteFlyer(f.uploadedKey!);
                            } catch (_) {}
                          }
                        },
                      )),
                  AddFlyerTile(onPick: _pickSingleFile),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ShadButton(
                    onPressed: _pickFiles,
                    child: const Text('Upload files'),
                  ),
                  const SizedBox(width: 8),
                  ShadButton.outline(
                    onPressed: () {
                      setState(() {
                        _flyerCtrls.add(TextEditingController());
                      });
                    },
                    child: const Text('Add URL'),
                  ),
                ],
              ),
              if (_flyerCtrls.isNotEmpty) ...[
                const SizedBox(height: 12),
                ..._flyerCtrls.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final ctrl = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: ShadInputFormField(
                            controller: ctrl,
                            label: Text('URL ${idx + 1}'),
                            placeholder: const Text('https://…'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ShadButton.ghost(
                          size: ShadButtonSize.sm,
                          onPressed: () {
                            setState(() {
                              _flyerCtrls.removeAt(idx).dispose();
                            });
                            _step1Baseline = _currentStep1Snapshot();
                          },
                          child: const Icon(Icons.delete_outline, size: 16),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        ShadCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Store details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'These fields help route orders and connect Stripe.',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 520;
                  final storeField = ShadInputFormField(
                    controller: _storeIdCtrl,
                    label: const Text('Store ID (slug)'),
                    readOnly: storeLocked,
                    validator: (v) => (v.isEmpty) ? 'Required' : null,
                  );
                  final typeField = DropdownButtonFormField<String>(
                    initialValue: _businessType,
                    decoration:
                        const InputDecoration(labelText: 'Business type'),
                    items: const [
                      DropdownMenuItem(
                          value: 'fast_food', child: Text('Fast Food')),
                      DropdownMenuItem(
                          value: 'auto_parts', child: Text('Auto Parts')),
                      DropdownMenuItem(
                          value: 'gas_station', child: Text('Gas Station')),
                    ],
                    onChanged: typeLocked
                        ? null
                        : (v) =>
                            setState(() => _businessType = v ?? 'fast_food'),
                  );
                  final currencyField = DropdownButtonFormField<String>(
                    initialValue: _currencyCode,
                    decoration: const InputDecoration(labelText: 'Currency'),
                    items: const [
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                      DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                      DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                    ],
                    onChanged: (v) =>
                        setState(() => _currencyCode = v ?? 'USD'),
                  );
                  final fuelPrepayField = ShadInputFormField(
                    controller: _fuelPrepayCtrl,
                    label: Text(
                        'Default fuel prepay (${_currencyCode.toUpperCase()})'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  );
                  if (stacked) {
                    return Column(
                      children: [
                        storeField,
                        const SizedBox(height: 10),
                        typeField,
                        if (_businessType == 'gas_station') ...[
                          const SizedBox(height: 10),
                          currencyField,
                          const SizedBox(height: 10),
                          fuelPrepayField,
                        ],
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: storeField),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            typeField,
                            if (_businessType == 'gas_station') ...[
                              const SizedBox(height: 10),
                              currencyField,
                              const SizedBox(height: 10),
                              fuelPrepayField,
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepVoiceClone() {
    final cs = Theme.of(context).colorScheme;
    final voiceReady = _totalRecordedDuration().inSeconds >= 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShadCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Voice selection (optional)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Pick an existing ElevenLabs voice or create a new one below.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _voiceId != null && _voiceId!.isNotEmpty
                          ? _voiceId
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Existing voices',
                      ),
                      items: _voiceOptions
                          .map((v) => DropdownMenuItem(
                                value: v.id,
                                child: Text(v.name.isEmpty ? v.id : v.name),
                              ))
                          .toList(),
                      onChanged: _voiceSaving
                          ? null
                          : (value) {
                              if (value == null) return;
                              _saveSelectedVoice(value);
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
            ],
          ),
        ),
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
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
              body:
                  'Background sounds interfere with recording quality results.',
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
                          ? _RecordingStopButton(
                              onPressed: _stopRecording,
                            )
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
                    _WaveformBars(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    const Spacer(),
                    _TimePill(
                      text: '${_formatClock(_recordingElapsed)}  /  00:30',
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
                            ? _formatClock(sample.duration!)
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
                  onPressed: () =>
                      setState(() => _voiceSamples.removeAt(index)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          );
        }),
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
              onPressed:
                  voiceReady ? () => setState(() => _voiceCloneStep = 1) : null,
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
                child: Text('Label',
                    style: TextStyle(fontWeight: FontWeight.w600))),
            SizedBox(width: 10),
            Expanded(
                child: Text('Value',
                    style: TextStyle(fontWeight: FontWeight.w600))),
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
        }),
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
              onPressed: () => _setStep(_stepIngestion),
              child: const Text('Skip'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _step2() {
    final cs = Theme.of(context).colorScheme;
    final demoSkip = _demoSkipStripe;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShadCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Stripe onboarding',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                demoSkip
                    ? 'Demo mode is enabled for this tenant. You can skip Stripe for now and finalize later.'
                    : 'Complete Stripe onboarding to enable payouts and account verification.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (demoSkip) ...[
                ShadAlert(
                  title: const Text('Demo mode: Stripe skipped'),
                  description: const Text(
                    'This bypass is intended for dev demos only. For a real onboarding, complete Stripe later.',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_stripeAccountId != null) ...[
                ShadAlert(
                  title: const Text('Stripe account created'),
                  description: Text(_stripeAccountId!),
                ),
                const SizedBox(height: 12),
                ShadButton(
                  onPressed: () async {
                    try {
                      final api = ref.read(tenantApiProvider);
                      final sessionId = await _ensureSession(api);
                      final url =
                          await api.createStripeEmbeddedSession(sessionId);
                      if (!await launchUrl(Uri.parse(url),
                          mode: LaunchMode.externalApplication)) {
                        throw Exception('Could not launch Stripe onboarding');
                      }
                    } catch (e) {
                      if (!mounted) return;
                      showShadSnack(context,
                          title: 'Stripe link failed',
                          message: '$e',
                          type: ShadSnackType.error);
                    }
                  },
                  child: const Text('Continue in Stripe'),
                ),
                const SizedBox(height: 10),
                Text(
                  'A new browser tab will open with embedded Stripe onboarding. When finished, come back here and press Next.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ] else if (!demoSkip) ...[
                Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Creating Stripe account…',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ] else ...[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ShadButton.outline(
                      onPressed: _statusLoading ? null : _startStripeOnboarding,
                      child: const Text('Create Stripe account anyway'),
                    ),
                    Text(
                      'Optional. You can still press Next to skip.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _step3() {
    final cs = Theme.of(context).colorScheme;
    final status = (_ingestStatus ?? 'not_started').toLowerCase();
    final inProgress = ['queued', 'processing', 'ingesting'].contains(status);
    final done = ['succeeded', 'partial_ok'].contains(status);
    final failed = ['error', 'failed', 'canceled'].contains(status);
    final pct = _ingestProgress;
    final pctLabel = pct == null ? null : '${(pct * 100).round()}%';

    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fast menu ingestion',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Menu-only extraction (text-only). This is demo-ready once complete; images can be enriched in the next step.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ShadBadge.secondary(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text('Status: ${_ingestStatus ?? 'not started'}'),
              ),
              if (_ingestJobIds.isNotEmpty)
                ShadBadge.secondary(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('Jobs: ${_ingestJobIds.length}'),
                ),
              if (_ingestStage != null)
                ShadBadge.secondary(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('Stage: ${_ingestStage!}'),
                ),
              if (pctLabel != null)
                ShadBadge.secondary(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(pctLabel),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_ingestJobIds.isNotEmpty || inProgress || done || failed) ...[
            _ingestStageViz(status: status, stage: _ingestStage, progress: pct),
            const SizedBox(height: 12),
          ],
          if (_ingestJobIds.isNotEmpty) ...[
            Text(
              'Job IDs',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            ..._ingestJobIds.map(
                (j) => Text(j, style: TextStyle(color: cs.onSurfaceVariant))),
            const SizedBox(height: 12),
          ],
          if (inProgress) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: ShadProgress(value: pct),
                ),
                const SizedBox(height: 8),
                Text(
                  pctLabel != null
                      ? 'Processing… $pctLabel'
                      : (_ingestPolling ? 'Updating…' : 'In progress…'),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (failed) ...[
            ShadAlert.destructive(
              title: Text(status == 'canceled'
                  ? 'Ingestion canceled'
                  : 'Ingestion failed'),
              description: Text('Status: ${_ingestStatus ?? 'unknown'}'),
            ),
            const SizedBox(height: 10),
          ],
          if (done) ...[
            ShadAlert(
              title: const Text('Fast ingestion complete'),
              description: const Text(
                  'Demo-ready: publish the menu and verify the snapshot, then you can run the live demo.'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ShadButton(
                  onPressed: (_publishingMenu || _menuPublished)
                      ? null
                      : _publishMenuToAgent,
                  child: _publishingMenu
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_menuPublished
                          ? 'Menu published'
                          : 'Publish menu to agent'),
                ),
                if (_menuPublished && _menuPublishedJobId != null)
                  ShadBadge.secondary(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text('Published: $_menuPublishedJobId'),
                  ),
                ShadButton.outline(
                  onPressed:
                      _verifyingMenuSnapshot ? null : _verifyAgentMenuSnapshot,
                  child: _verifyingMenuSnapshot
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Verify agent menu snapshot'),
                ),
                if (_menuSnapshotCheckedAt != null)
                  ShadBadge.secondary(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      _menuSnapshotItemCount == null
                          ? 'Snapshot: not found'
                          : 'Snapshot: ${_menuSnapshotItemCount!} items',
                    ),
                  ),
                ShadButton(
                  onPressed: () => context.go('/demo'),
                  child: const Text('Open Live Demo'),
                ),
                Text(
                  'Then select this tenant and start the ElevenLabs widget.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                'AI workflow',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                _workflowVisible ? 'Shown' : 'Hidden',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: _workflowVisible,
                onChanged:
                    (_ingestJobIds.isEmpty && !inProgress && !done && !failed)
                        ? null
                        : (v) async {
                            setState(() => _workflowVisible = v);
                            if (v) {
                              await _pollWorkflowOnce(force: true);
                            }
                          },
              ),
            ],
          ),
          if (_workflowVisible) ...[
            const SizedBox(height: 10),
            _workflowGraph(),
            const SizedBox(height: 14),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ShadButton(
                onPressed: (_ingestTriggering || inProgress)
                    ? null
                    : _triggerIngestion,
                child: _ingestTriggering
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_ingestJobIds.isEmpty
                        ? 'Start fast ingestion'
                        : 'Restart fast ingestion'),
              ),
              ShadButton.outline(
                onPressed: _ingestPolling ? null : _pollIngestOnce,
                child: Text(_ingestPolling ? 'Refreshing…' : 'Refresh'),
              ),
              if (inProgress && _ingestJobIds.isNotEmpty)
                ShadButton.outline(
                  onPressed: _ingestCanceling ? null : _cancelIngestion,
                  child: _ingestCanceling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Cancel ingestion'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepImageEnrichment() {
    final cs = Theme.of(context).colorScheme;
    final jobId = _latestIngestJobId();
    final status = (_ingestStatus ?? 'not_started').toLowerCase();
    final inProgress = ['queued', 'processing', 'ingesting'].contains(status);
    final failed = ['error', 'failed', 'canceled'].contains(status);
    final pct = _ingestProgress;
    final pctLabel = pct == null ? null : '${(pct * 100).round()}%';

    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Image enrichment (optional)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Adds thumbnails/photos to the already-extracted menu. This does not change item IDs; it only enriches images. You can skip this for a voice-only demo.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (jobId == null) ...[
            ShadAlert.destructive(
              title: const Text('No ingestion job yet'),
              description: const Text('Run Fast ingestion first.'),
            ),
          ] else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ShadBadge.secondary(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('Job: $jobId'),
                ),
                ShadBadge.secondary(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('Status: ${_ingestStatus ?? 'unknown'}'),
                ),
                if (_ingestStage != null)
                  ShadBadge.secondary(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text('Stage: ${_ingestStage!}'),
                  ),
                if (pctLabel != null)
                  ShadBadge.secondary(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(pctLabel),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _ingestStageViz(status: status, stage: _ingestStage, progress: pct),
            const SizedBox(height: 12),
            if (failed) ...[
              ShadAlert.destructive(
                title: Text(status == 'canceled'
                    ? 'Enrichment canceled'
                    : 'Enrichment failed'),
                description: Text('Status: ${_ingestStatus ?? 'unknown'}'),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ShadButton(
                  onPressed:
                      (!_fastIngestReady || _ingestResumingImages || inProgress)
                          ? null
                          : _resumeImageEnrichment,
                  child: _ingestResumingImages
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(
                          inProgress ? 'Enriching…' : 'Start image enrichment'),
                ),
                ShadButton.outline(
                  onPressed: _ingestPolling ? null : _pollIngestOnce,
                  child: Text(_ingestPolling ? 'Refreshing…' : 'Refresh'),
                ),
                ShadButton.outline(
                  onPressed: () => _setStep(_stepAgent),
                  child: const Text('Skip → Agent'),
                ),
                Text(
                  'You can continue while enrichment runs.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _workflowGraph({bool fullscreen = false, bool showHeader = true}) {
    final cs = Theme.of(context).colorScheme;
    if (_workflowLoading && _workflowNodes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (_workflowNodes.isEmpty) {
      return ShadAlert(
        title: const Text('No workflow yet'),
        description:
            const Text('Start ingestion to see per-AI-call nodes here.'),
      );
    }

    final layout = _WorkflowLayout.compute(_workflowNodes);
    final nodesById = {for (final n in _workflowNodes) n.id: n};
    final nodeOrder = [..._workflowNodes]
      ..sort((a, b) => a.seq.compareTo(b.seq));
    final active = _activeWorkflowNode();
    final activeParent =
        active?.parentId != null ? nodesById[active!.parentId!] : null;

    final header = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ShadBadge.secondary(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text('Nodes: ${_workflowNodes.length}'),
        ),
        if (_workflowJobId != null)
          ShadBadge.secondary(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text('Job: $_workflowJobId'),
          ),
        ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: _workflowPollInFlight
              ? null
              : () => _pollWorkflowOnce(force: true),
          child:
              Text(_workflowPollInFlight ? 'Refreshing…' : 'Refresh workflow'),
        ),
        if (!fullscreen)
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: _openWorkflowFullscreen,
            child: const Text('Fullscreen'),
          ),
        if (_workflowSelectedId != null)
          ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: () => _selectWorkflowNode(null),
            child: const Text('Clear selection'),
          ),
      ],
    );

    final graph = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        height: fullscreen ? 760 : 420,
        child: InteractiveViewer(
          minScale: 0.35,
          maxScale: 2.8,
          constrained: false,
          child: SizedBox(
            width: layout.size.width,
            height: layout.size.height,
            child: Stack(
              children: [
                CustomPaint(
                  size: layout.size,
                  painter: _WorkflowEdgePainter(
                      nodes: nodeOrder, positions: layout.positions),
                ),
                ...nodeOrder.map((n) {
                  final pos = layout.positions[n.id];
                  if (pos == null) return const SizedBox.shrink();
                  final selected = _workflowSelectedId == n.id;
                  final hovered = _workflowHoveredId == n.id;
                  return Positioned(
                    left: pos.dx,
                    top: pos.dy,
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _workflowHoveredId = n.id),
                      onExit: (_) => setState(() => _workflowHoveredId = null),
                      child: _WorkflowNodeCard(
                        node: n,
                        parent:
                            n.parentId != null ? nodesById[n.parentId!] : null,
                        selected: selected || (!selected && hovered),
                        onTap: () => _selectWorkflowNode(n.id),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );

    final details = ShadCard(
      padding: const EdgeInsets.all(12),
      child: active == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Details',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  'Click a node to inspect outputs (image/text).',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            )
          : _WorkflowNodeDetails(
              node: active,
              parent: activeParent,
              onOpenImage: _showImagePreview,
            ),
    );

    return ShadCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            header,
            const SizedBox(height: 12),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              if (!wide) {
                return Column(
                  children: [
                    graph,
                    const SizedBox(height: 12),
                    details,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: graph),
                  const SizedBox(width: 12),
                  SizedBox(width: 360, child: details),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Tip: drag to pan, scroll to zoom.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _step4() {
    final cs = Theme.of(context).colorScheme;
    final typeLabel = _businessType == 'auto_parts'
        ? 'Auto Parts'
        : _businessType == 'gas_station'
            ? 'Gas Station'
            : 'Fast Food';
    final storeId = _storeIdCtrl.text.trim();
    final tenantId = widget.tenantId.trim();
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create agent',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'We’ll bind this tenant to the shared ElevenLabs agent template for this business type (no per-tenant duplication).',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ShadBadge.secondary(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text('Type: $typeLabel'),
              ),
              if (_agentId != null && _agentId!.isNotEmpty)
                ShadBadge.secondary(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('Agent: ${_agentId!}'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ShadCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Runtime variables',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                    'These must be provided to the agent (dynamic variables) so tools hit the right store.'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ShadBadge.secondary(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Text(
                          'storeId: ${storeId.isEmpty ? '(unset)' : storeId}'),
                    ),
                    ShadBadge.secondary(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Text(
                          'tenantId: ${tenantId.isEmpty ? '(unset)' : tenantId}'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ShadButton(
                onPressed: (_agentCreating || _step4Valid())
                    ? null
                    : () => _createAgent(auto: false),
                child: _agentCreating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        _step4Valid() ? 'Agent configured' : 'Configure agent'),
              ),
              if (_step4Valid())
                ShadButton.outline(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _agentId!));
                    if (!mounted) return;
                    showShadSnack(
                      context,
                      title: 'Copied',
                      message:
                          'ElevenLabs template agent id copied to clipboard.',
                      type: ShadSnackType.success,
                    );
                  },
                  child: const Text('Copy agent id'),
                ),
            ],
          ),
          if (!_step4Valid()) ...[
            const SizedBox(height: 10),
            Text(
              'This step is required before finalizing (tenant → agent template binding).',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _step5() {
    final cs = Theme.of(context).colorScheme;
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Finalize',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'We’ll create/update the tenant store record and mark onboarding as ready.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_sessionId != null)
                ShadBadge.secondary(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('Session: $_sessionId'),
                ),
              ShadBadge.secondary(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text('Store: ${_storeIdCtrl.text}'),
              ),
              ShadBadge.secondary(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text('Type: $_businessType'),
              ),
              ShadBadge.secondary(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text('Ingest: ${_ingestStatus ?? 'unknown'}'),
              ),
              if (_agentId != null && _agentId!.isNotEmpty)
                ShadBadge.secondary(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('Agent: ${_agentId!}'),
                ),
              if (_stripeAccountId != null)
                ShadBadge.secondary(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('Stripe: ${_stripeAccountId!}'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ShadButton.outline(
                onPressed: _statusLoading ? null : _checkStatus,
                child: _statusLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Refresh status'),
              ),
              ShadButton(
                onPressed:
                    (_finalizeLoading || !_step3Valid() || !_step4Valid())
                        ? null
                        : _finalize,
                child: _finalizeLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Finalize'),
              ),
            ],
          ),
          if (!_step3Valid() || !_step4Valid()) ...[
            const SizedBox(height: 10),
            Text(
              'Finalize is enabled once fast ingestion has produced a draft menu and an agent is created. Image enrichment is optional.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Future<String> _ensureSession(TenantApi api) async {
    if (_sessionId != null) return _sessionId!;
    final id = await api.startSession(
      tenantId: widget.tenantId,
      storeId:
          _storeIdCtrl.text.trim().isEmpty ? null : _storeIdCtrl.text.trim(),
    );
    setState(() => _sessionId = id);
    return id;
  }

  Future<void> _attachFlyers(TenantApi api, String sessionId) async {
    final urls = _currentFlyerUrls();
    if (urls.isEmpty) return;
    await api.attachFlyers(sessionId, urls);
  }

  Future<void> _pickFiles({bool multiple = true}) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: multiple,
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'pdf'],
      withData: true,
    );
    if (result == null) return;
    for (final file in result.files) {
      if (file.bytes == null) continue;
      final mime = _guessMime(file.extension);
      final attachment =
          FlyerAttachment(name: file.name, bytes: file.bytes!, mime: mime);
      setState(() => _flyers.add(attachment));
      _uploadFlyer(attachment, file);
    }
  }

  Future<void> _pickSingleFile() => _pickFiles(multiple: false);

  Future<void> _uploadFlyer(FlyerAttachment att, PlatformFile file) async {
    setState(() => att.uploading = true);
    try {
      final result = await ref.read(tenantApiProvider).uploadFlyer(file);
      setState(() {
        att.uploadedUrl = result['url'];
        att.uploadedKey = result['key'];
        att.error = null;
      });
    } catch (e) {
      setState(() => att.error = e.toString());
    } finally {
      setState(() => att.uploading = false);
    }
  }

  List<String> _currentFlyerUrls() {
    final manual = _flyerCtrls
        .map((c) => c.text.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    final uploaded = _flyers
        .where((f) => f.uploadedUrl != null)
        .map((f) => f.uploadedUrl!)
        .toList();
    return [...manual, ...uploaded];
  }

  String _guessMime(String? ext) {
    final lower = (ext ?? '').toLowerCase();
    switch (lower) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resumeLoading) {
      return const AdminScaffold(
        title: Text('Onboard Business'),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(height: 12),
              Text('Loading onboarding…'),
            ],
          ),
        ),
      );
    }
    final stepContent = switch (_step) {
      _stepMenu => _step1(),
      _stepVoice => _stepVoiceClone(),
      _stepIngestion => _step3(),
      _stepImages => _stepImageEnrichment(),
      _stepAgent => _step4(),
      _stepStripe => _step2(),
      _ => _step5(), // finalize
    };
    return AdminScaffold(
      title: const Text('Onboard Business'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Onboard business',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Upload flyers, run fast menu ingestion, optionally enrich images, then continue with agent + Stripe + finalize.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  _stepIndicator(),
                  const SizedBox(height: 14),
                  stepContent,
                  const SizedBox(height: 16),
                  if (_error != null)
                    ShadAlert.destructive(
                      title: const Text('Failed'),
                      description: Text(_error!),
                    ),
                  const SizedBox(height: 12),
                  _stepperControls(),
                ],
              ),
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
            color: active ? null : cs.onSurfaceVariant,
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
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
  });

  final Widget child;
  final Color color;
  static const double _radius = 16;
  static const double _dashLength = 6;
  static const double _gapLength = 4;
  static const double _strokeWidth = 1.2;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: color,
        radius: _radius,
        dashLength: _dashLength,
        gapLength: _gapLength,
        strokeWidth: _strokeWidth,
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

class _Step1Snapshot {
  const _Step1Snapshot({
    required this.storeId,
    required this.businessType,
    required this.country,
    required this.flyerUrls,
    required this.currency,
    required this.fuelDefaultPrepayCents,
  });

  final String storeId;
  final String businessType;
  final String country;
  final List<String> flyerUrls;
  final String currency;
  final int fuelDefaultPrepayCents;

  factory _Step1Snapshot.empty() => const _Step1Snapshot(
      storeId: '',
      businessType: '',
      country: '',
      flyerUrls: <String>[],
      currency: '',
      fuelDefaultPrepayCents: 0);

  List<String> get _normalizedFlyers {
    final out = flyerUrls
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    out.sort();
    return out;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _Step1Snapshot) return false;
    return storeId.trim() == other.storeId.trim() &&
        businessType.trim() == other.businessType.trim() &&
        country.trim() == other.country.trim() &&
        currency.trim() == other.currency.trim() &&
        fuelDefaultPrepayCents == other.fuelDefaultPrepayCents &&
        _listEq(_normalizedFlyers, other._normalizedFlyers);
  }

  @override
  int get hashCode {
    final flyers = _normalizedFlyers;
    var h = Object.hash(
      storeId.trim(),
      businessType.trim(),
      country.trim(),
      currency.trim(),
      fuelDefaultPrepayCents,
    );
    for (final f in flyers) {
      h = Object.hash(h, f);
    }
    return h;
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _IngestStageSpec {
  const _IngestStageSpec({
    required this.key,
    required this.label,
    required this.icon,
  });

  final String key;
  final String label;
  final IconData icon;
}

class _WorkflowTraceNode {
  const _WorkflowTraceNode({
    required this.id,
    required this.parentId,
    required this.kind,
    required this.label,
    required this.status,
    required this.seq,
    required this.page,
    required this.itemIndex,
    required this.modelId,
    required this.error,
    required this.meta,
  });

  final String id;
  final String? parentId;
  final String kind;
  final String label;
  final String status;
  final int seq;
  final int? page;
  final int? itemIndex;
  final String? modelId;
  final String? error;
  final Map<String, dynamic>? meta;

  factory _WorkflowTraceNode.fromJson(Map<String, dynamic> json) {
    final seqRaw = json['seq'];
    final pageRaw = json['page'];
    final itemRaw = json['itemIndex'];
    final metaRaw = json['meta'];
    return _WorkflowTraceNode(
      id: (json['id'] as String?) ?? '',
      parentId: json['parentId'] as String?,
      kind: (json['kind'] as String?) ?? '',
      label: (json['label'] as String?) ?? (json['id'] as String? ?? ''),
      status: ((json['status'] as String?) ?? 'queued').toLowerCase(),
      seq: seqRaw is num ? seqRaw.toInt() : 1 << 30,
      page: pageRaw is num ? pageRaw.toInt() : null,
      itemIndex: itemRaw is num ? itemRaw.toInt() : null,
      modelId: json['modelId'] as String?,
      error: json['error'] as String?,
      meta: metaRaw is Map ? metaRaw.cast<String, dynamic>() : null,
    );
  }

  bool get isDone => status == 'succeeded';
  bool get isRunning => status == 'running' || status == 'queued';
  bool get isError => status == 'error';
  bool get isCanceled => status == 'canceled';
  bool get isSkipped => status == 'skipped';
}

class _WorkflowLayout {
  const _WorkflowLayout({required this.positions, required this.size});
  final Map<String, Offset> positions;
  final Size size;

  static const double nodeW = 240;
  static const double nodeH = 74;
  static const double hGap = 74;
  static const double vGap = 28;
  static const double pad = 24;

  static _WorkflowLayout compute(List<_WorkflowTraceNode> nodes) {
    final byId = <String, _WorkflowTraceNode>{
      for (final n in nodes)
        if (n.id.isNotEmpty) n.id: n,
    };
    final children = <String, List<String>>{};
    final roots = <String>[];

    for (final n in nodes) {
      if (n.id.isEmpty) continue;
      final pid = n.parentId;
      if (pid != null && pid.isNotEmpty && byId.containsKey(pid)) {
        children.putIfAbsent(pid, () => []).add(n.id);
      } else {
        roots.add(n.id);
      }
    }

    int seqOf(String id) => byId[id]?.seq ?? (1 << 30);
    for (final entry in children.entries) {
      entry.value.sort((a, b) => seqOf(a).compareTo(seqOf(b)));
    }
    roots.sort((a, b) => seqOf(a).compareTo(seqOf(b)));

    final depth = <String, int>{};
    final y = <String, double>{};
    double cursor = pad;

    double assign(String id, int d) {
      depth[id] = d;
      final kids = children[id] ?? const <String>[];
      if (kids.isEmpty) {
        final yy = cursor;
        y[id] = yy;
        cursor += nodeH + vGap;
        return yy;
      }
      final childYs = <double>[];
      for (final k in kids) {
        childYs.add(assign(k, d + 1));
      }
      final yy = childYs.reduce((a, b) => a + b) / childYs.length;
      y[id] = yy;
      return yy;
    }

    for (final r in roots) {
      assign(r, 0);
      cursor += vGap; // gap between root subtrees
    }

    int maxDepth = 0;
    for (final d in depth.values) {
      if (d > maxDepth) maxDepth = d;
    }

    final positions = <String, Offset>{};
    double maxY = 0;
    for (final id in byId.keys) {
      final d = depth[id] ?? 0;
      final yy = y[id] ?? pad;
      final xx = pad + d * (nodeW + hGap);
      positions[id] = Offset(xx, yy);
      maxY = math.max(maxY, yy);
    }

    final width =
        pad * 2 + (maxDepth + 1) * nodeW + math.max(0, maxDepth) * hGap;
    final height = math.max(pad * 2 + nodeH, maxY + nodeH + pad);
    return _WorkflowLayout(positions: positions, size: Size(width, height));
  }
}

class _WorkflowEdgePainter extends CustomPainter {
  _WorkflowEdgePainter({required this.nodes, required this.positions});
  final List<_WorkflowTraceNode> nodes;
  final Map<String, Offset> positions;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final n in nodes) {
      final pid = n.parentId;
      if (pid == null || pid.isEmpty) continue;
      final from = positions[pid];
      final to = positions[n.id];
      if (from == null || to == null) continue;

      final p1 = Offset(
          from.dx + _WorkflowLayout.nodeW, from.dy + _WorkflowLayout.nodeH / 2);
      final p2 = Offset(to.dx, to.dy + _WorkflowLayout.nodeH / 2);

      final color = n.isError
          ? Colors.red
          : n.isCanceled
              ? Colors.orange
              : n.isDone
                  ? Colors.green
                  : Colors.blueGrey;
      paint.color = color.withValues(alpha: 0.65);

      final dx = (p2.dx - p1.dx).abs();
      final c1 = Offset(p1.dx + math.min(90, dx / 2), p1.dy);
      final c2 = Offset(p2.dx - math.min(90, dx / 2), p2.dy);
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WorkflowEdgePainter oldDelegate) =>
      oldDelegate.nodes != nodes || oldDelegate.positions != positions;
}

class _WorkflowNodeCard extends StatelessWidget {
  const _WorkflowNodeCard({
    required this.node,
    required this.parent,
    required this.selected,
    required this.onTap,
  });
  final _WorkflowTraceNode node;
  final _WorkflowTraceNode? parent;
  final bool selected;
  final VoidCallback onTap;

  IconData _iconForKind(String kind) {
    switch (kind) {
      case 'analysis':
        return Icons.text_snippet_outlined;
      case 'composite':
      case 'composite_agent':
        return Icons.grid_view_outlined;
      case 'count':
        return Icons.numbers;
      case 'render_item':
        return Icons.crop;
      case 'describe_thumb':
        return Icons.link;
      default:
        return Icons.bubble_chart_outlined;
    }
  }

  Color _statusColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (node.isError) return cs.error;
    if (node.isCanceled) return Colors.orange;
    if (node.isSkipped) return cs.outline;
    if (node.isDone) return Colors.green;
    if (node.isRunning) return ShadTheme.of(context).colorScheme.primary;
    return cs.outlineVariant;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _statusColor(context);
    final subtitleParts = <String>[];
    if (node.modelId != null && node.modelId!.isNotEmpty) {
      subtitleParts.add(node.modelId!);
    }
    if (node.page != null) subtitleParts.add('p${node.page}');
    if (node.itemIndex != null) subtitleParts.add('i${node.itemIndex}');
    final subtitle = subtitleParts.join(' • ');

    return SizedBox(
      width: _WorkflowLayout.nodeW,
      height: _WorkflowLayout.nodeH,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: selected
                ? Border.all(
                    color: ShadTheme.of(context).colorScheme.primary, width: 2)
                : null,
          ),
          child: ShadCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(_iconForKind(node.kind), size: 18, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              subtitle.isEmpty
                                  ? node.status
                                  : '$subtitle • ${node.status}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (node.isRunning)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (node.isError)
                  Tooltip(
                    message: node.error ?? 'error',
                    child: Icon(Icons.error_outline, size: 16, color: cs.error),
                  )
                else
                  const SizedBox(width: 14, height: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkflowNodeDetails extends StatelessWidget {
  const _WorkflowNodeDetails({
    required this.node,
    required this.parent,
    required this.onOpenImage,
  });
  final _WorkflowTraceNode node;
  final _WorkflowTraceNode? parent;
  final void Function(String url) onOpenImage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = node.meta ?? const <String, dynamic>{};
    final url = meta['url'] is String ? meta['url'] as String : null;
    final dest = meta['dest'] is String ? meta['dest'] as String : null;
    final result = meta['result'];
    final metaSansUrl = Map<String, dynamic>.from(meta)..remove('url');

    String? prettyJson(dynamic v) {
      try {
        if (v == null) return null;
        const enc = JsonEncoder.withIndent('  ');
        return enc.convert(v);
      } catch (_) {
        return v.toString();
      }
    }

    final jsonText = prettyJson(result);
    final metaText = (jsonText == null || jsonText.isEmpty)
        ? prettyJson(metaSansUrl.isEmpty ? null : metaSansUrl)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(node.label, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ShadBadge.secondary(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text('Status: ${node.status}'),
            ),
            ShadBadge.secondary(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text('Kind: ${node.kind}'),
            ),
            if (node.modelId != null)
              ShadBadge.secondary(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(node.modelId!),
              ),
            if (node.page != null)
              ShadBadge.secondary(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text('Page ${node.page}'),
              ),
            if (node.itemIndex != null)
              ShadBadge.secondary(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text('Item ${node.itemIndex}'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (parent != null)
          Text(
            'Parent: ${parent!.label}',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        if (node.error != null && node.error!.isNotEmpty) ...[
          const SizedBox(height: 8),
          ShadAlert.destructive(
            title: const Text('Error'),
            description: Text(node.error!),
          ),
        ],
        if (url != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Output',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                },
                child: const Text('Copy URL'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => onOpenImage(url),
            borderRadius: BorderRadius.circular(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                height: 220,
                alignment: Alignment.center,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Image failed to load: $error',
                        style: TextStyle(color: cs.error)),
                  ),
                ),
              ),
            ),
          ),
          if (dest != null) ...[
            const SizedBox(height: 8),
            Text('GCS: $dest',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ],
        ],
        if (jsonText != null && jsonText.isNotEmpty && node.isDone) ...[
          const SizedBox(height: 10),
          const Text('Result', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: SelectableText(
              jsonText,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
        if (metaText != null && metaText.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Metadata', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: SelectableText(
              metaText,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
        if ((url == null || !node.isDone) &&
            (jsonText == null || jsonText.isEmpty) &&
            (metaText == null || metaText.isEmpty)) ...[
          const SizedBox(height: 10),
          Text(
            'No output captured for this node yet.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _WorkflowFullscreenDialog extends ConsumerStatefulWidget {
  const _WorkflowFullscreenDialog({
    required this.sessionId,
    required this.initialNodes,
    required this.initialJobId,
  });

  final String sessionId;
  final List<_WorkflowTraceNode> initialNodes;
  final String? initialJobId;

  @override
  ConsumerState<_WorkflowFullscreenDialog> createState() =>
      _WorkflowFullscreenDialogState();
}

class _WorkflowFullscreenDialogState
    extends ConsumerState<_WorkflowFullscreenDialog> {
  bool _loading = false;
  bool _inFlight = false;
  String? _jobId;
  List<_WorkflowTraceNode> _nodes = const [];
  String? _selectedId;
  String? _hoveredId;

  @override
  void initState() {
    super.initState();
    _nodes = widget.initialNodes;
    _jobId = widget.initialJobId;
    if (_nodes.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  _WorkflowTraceNode? _active() {
    final id = _selectedId ?? _hoveredId;
    if (id == null) return null;
    for (final n in _nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  Future<void> _refresh() async {
    if (_inFlight) return;
    _inFlight = true;
    if (mounted) setState(() => _loading = true);
    try {
      final api = ref.read(tenantApiProvider);
      final resp = await api.ingestWorkflow(widget.sessionId, limit: 2000);
      final nodesRaw = resp['nodes'] as List<dynamic>? ?? const [];
      final jobId = resp['job_id'] as String?;
      final nodes = <_WorkflowTraceNode>[];
      for (final n in nodesRaw) {
        if (n is Map<String, dynamic>) {
          nodes.add(_WorkflowTraceNode.fromJson(n));
        } else if (n is Map) {
          nodes.add(_WorkflowTraceNode.fromJson(n.cast<String, dynamic>()));
        }
      }
      nodes.sort((a, b) => a.seq.compareTo(b.seq));
      if (!mounted) return;
      setState(() {
        _jobId = jobId;
        _nodes = nodes;
      });
    } catch (_) {
      // ignore
    } finally {
      _inFlight = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showImage(String url) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: SizedBox(
            width: MediaQuery.of(ctx).size.width * 0.92,
            height: MediaQuery.of(ctx).size.height * 0.92,
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Preview',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    ShadButton.ghost(
                      size: ShadButtonSize.sm,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: url));
                      },
                      child: const Text('Copy URL'),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.4,
                    maxScale: 4.0,
                    child: Center(
                      child: Image.network(url, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nodesById = {for (final n in _nodes) n.id: n};
    final active = _active();
    final activeParent =
        active?.parentId != null ? nodesById[active!.parentId!] : null;

    final header = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_jobId != null)
          ShadBadge.secondary(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text('Job: $_jobId'),
          ),
        ShadBadge.secondary(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text('Nodes: ${_nodes.length}'),
        ),
        ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: _inFlight ? null : _refresh,
          child: Text(_inFlight ? 'Refreshing…' : 'Refresh'),
        ),
        if (_selectedId != null)
          ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: () => setState(() => _selectedId = null),
            child: const Text('Clear selection'),
          ),
      ],
    );

    Widget content;
    if (_nodes.isEmpty) {
      content = Center(
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))
            : ShadAlert(
                title: const Text('No workflow yet'),
                description: const Text('Start ingestion, then refresh.'),
              ),
      );
    } else {
      final layout = _WorkflowLayout.compute(_nodes);
      final nodeOrder = [..._nodes]..sort((a, b) => a.seq.compareTo(b.seq));
      final graph = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          child: InteractiveViewer(
            minScale: 0.35,
            maxScale: 3.0,
            constrained: false,
            child: SizedBox(
              width: layout.size.width,
              height: layout.size.height,
              child: Stack(
                children: [
                  CustomPaint(
                    size: layout.size,
                    painter: _WorkflowEdgePainter(
                        nodes: nodeOrder, positions: layout.positions),
                  ),
                  ...nodeOrder.map((n) {
                    final pos = layout.positions[n.id];
                    if (pos == null) return const SizedBox.shrink();
                    final selected = _selectedId == n.id;
                    final hovered = _hoveredId == n.id;
                    return Positioned(
                      left: pos.dx,
                      top: pos.dy,
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _hoveredId = n.id),
                        onExit: (_) => setState(() => _hoveredId = null),
                        child: _WorkflowNodeCard(
                          node: n,
                          parent: n.parentId != null
                              ? nodesById[n.parentId!]
                              : null,
                          selected: selected || (!selected && hovered),
                          onTap: () => setState(() => _selectedId = n.id),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      );

      final details = ShadCard(
        padding: const EdgeInsets.all(12),
        child: active == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Details',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'Click a node to inspect outputs (image/text).',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              )
            : _WorkflowNodeDetails(
                node: active, parent: activeParent, onOpenImage: _showImage),
      );

      content = LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          if (!wide) {
            return Column(
              children: [
                SizedBox(height: 520, child: graph),
                const SizedBox(height: 12),
                details,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SizedBox(height: 760, child: graph)),
              const SizedBox(width: 12),
              SizedBox(width: 380, child: details),
            ],
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI workflow'),
        actions: [
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: 12),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}
