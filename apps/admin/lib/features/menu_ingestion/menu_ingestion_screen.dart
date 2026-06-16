import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../widgets/admin_scaffold.dart';
import '../../widgets/shad_snackbar.dart';
import 'menu_ingestion_api.dart';
import 'menu_ingestion_models.dart';
import 'menu_ingestion_panes.dart';

class MenuIngestionScreen extends StatefulWidget {
  const MenuIngestionScreen({super.key, MenuIngestionApi? api}) : _api = api;

  final MenuIngestionApi? _api;

  @override
  State<MenuIngestionScreen> createState() => _MenuIngestionScreenState();
}

class _MenuIngestionScreenState extends State<MenuIngestionScreen> {
  late final MenuIngestionApi _api = widget._api ?? MenuIngestionApi();
  late Future<List<MenuJob>> _jobsFuture;

  MenuJob? _selected;
  DraftDetail? _draft;
  List<AgentJob> _agentJobs = const [];
  bool _agentEnabled = false;
  bool _loadingDraft = false;
  String? _draftError;
  String? _agentError;

  @override
  void initState() {
    super.initState();
    _jobsFuture = _api.fetchJobs();
    _refreshAgentJobs();
    _loadAgentConfig();
  }

  Future<void> _refreshJobs() async {
    final future = _api.fetchJobs();
    setState(() => _jobsFuture = future);
    await future;
  }

  Future<void> _loadDraft(MenuJob job) async {
    setState(() {
      _selected = job;
      _loadingDraft = true;
      _draftError = null;
    });
    try {
      final draft = await _api.loadDraft(job.id);
      if (!mounted) return;
      setState(() => _draft = draft);
    } catch (err) {
      if (!mounted) return;
      setState(() => _draftError = err.toString());
    } finally {
      if (mounted) setState(() => _loadingDraft = false);
    }
  }

  Future<void> _approve(MenuJob job) async {
    setState(() => _loadingDraft = true);
    try {
      await _api.approve(job.id);
      if (!mounted) return;
      showShadSnack(context, title: 'Published', type: ShadSnackType.success);
      setState(() => _jobsFuture = _api.fetchJobs());
    } catch (err) {
      if (!mounted) return;
      setState(() => _draftError = err.toString());
    } finally {
      if (mounted) setState(() => _loadingDraft = false);
    }
  }

  Future<void> _refreshAgentJobs() async {
    try {
      final jobs = await _api.loadAgentJobs();
      if (!mounted) return;
      setState(() {
        _agentJobs = jobs;
        _agentError = null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _agentError = err.toString());
    }
  }

  Future<void> _loadAgentConfig() async {
    try {
      final enabled = await _api.loadAgentEnabled();
      if (!mounted) return;
      setState(() => _agentEnabled = enabled);
    } catch (err) {
      if (!mounted) return;
      setState(() => _agentError = err.toString());
    }
  }

  Future<void> _setAgentEnabled(bool enabled) async {
    final previous = _agentEnabled;
    setState(() => _agentEnabled = enabled);
    try {
      await _api.setAgentEnabled(enabled);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _agentEnabled = previous;
        _agentError = err.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: const Text('Menu Ingestion'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<List<MenuJob>>(
          future: _jobsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: ShadAlert.destructive(
                  title: const Text('Failed to load jobs'),
                  description: Text('${snapshot.error}'),
                ),
              );
            }
            return _MenuIngestionLayout(
              jobs: snapshot.data ?? const [],
              selected: _selected,
              draft: _draft,
              loadingDraft: _loadingDraft,
              draftError: _draftError,
              agentJobs: _agentJobs,
              agentEnabled: _agentEnabled,
              agentError: _agentError,
              onRefreshJobs: _refreshJobs,
              onSelectJob: _loadDraft,
              onApprove: _selected == null ? null : () => _approve(_selected!),
              onRefreshAgents: _refreshAgentJobs,
              onAgentToggle: _setAgentEnabled,
            );
          },
        ),
      ),
    );
  }
}

class _MenuIngestionLayout extends StatelessWidget {
  const _MenuIngestionLayout({
    required this.jobs,
    required this.selected,
    required this.draft,
    required this.loadingDraft,
    required this.draftError,
    required this.agentJobs,
    required this.agentEnabled,
    required this.agentError,
    required this.onRefreshJobs,
    required this.onSelectJob,
    required this.onApprove,
    required this.onRefreshAgents,
    required this.onAgentToggle,
  });

  final List<MenuJob> jobs;
  final MenuJob? selected;
  final DraftDetail? draft;
  final bool loadingDraft;
  final String? draftError;
  final List<AgentJob> agentJobs;
  final bool agentEnabled;
  final String? agentError;
  final Future<void> Function() onRefreshJobs;
  final void Function(MenuJob) onSelectJob;
  final VoidCallback? onApprove;
  final VoidCallback onRefreshAgents;
  final ValueChanged<bool> onAgentToggle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panes = _panes();
        if (constraints.maxWidth < 980) {
          return RefreshIndicator(
            onRefresh: onRefreshJobs,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: panes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (_, index) => panes[index],
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: panes[0]),
            const SizedBox(width: 16),
            Expanded(flex: 3, child: panes[1]),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: panes[2]),
          ],
        );
      },
    );
  }

  List<Widget> _panes() => [
        MenuJobsList(jobs: jobs, selected: selected, onSelect: onSelectJob),
        DraftPane(
          loading: loadingDraft,
          draft: draft,
          error: draftError,
          onApprove: onApprove,
        ),
        AgentQueuePane(
          jobs: agentJobs,
          onRefresh: onRefreshAgents,
          enabled: agentEnabled,
          onToggle: onAgentToggle,
          error: agentError,
        ),
      ];
}
