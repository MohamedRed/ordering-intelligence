import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../widgets/shad_snackbar.dart';
import '../../widgets/admin_scaffold.dart';

const _baseUrl = String.fromEnvironment(
  'MENU_INGESTION_BASE_URL',
  defaultValue: 'https://menu-ingestion-230152279015.us-central1.run.app',
);

class MenuIngestionScreen extends StatefulWidget {
  const MenuIngestionScreen({super.key});

  @override
  State<MenuIngestionScreen> createState() => _MenuIngestionScreenState();
}

class _MenuIngestionScreenState extends State<MenuIngestionScreen> {
  late Future<List<MenuJob>> _jobsFuture;
  MenuJob? _selected;
  DraftDetail? _draft;
  List<AgentJob> _agentJobs = [];
  bool _agentEnabled = false;
  bool _loadingDraft = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _jobsFuture = _fetchJobs();
    _loadAgentJobs();
    _loadAgentConfig();
  }

  Future<List<MenuJob>> _fetchJobs() async {
    final headers = await _authHeaders();
    final resp = await http.get(Uri.parse('$_baseUrl/ingest?limit=25'),
        headers: headers);
    if (resp.statusCode != 200) {
      throw Exception('Failed to load jobs (${resp.statusCode})');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final jobs = (data['jobs'] as List)
        .map((j) => MenuJob.fromJson(Map<String, dynamic>.from(j)))
        .toList();
    return jobs;
  }

  Future<void> _loadDraft(MenuJob job) async {
    setState(() {
      _selected = job;
      _loadingDraft = true;
      _error = null;
    });
    try {
      final headers = await _authHeaders();
      final resp = await http.get(Uri.parse('$_baseUrl/ingest/${job.id}/draft'),
          headers: headers);
      if (resp.statusCode != 200) {
        throw Exception('Draft load failed (${resp.statusCode})');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _draft = DraftDetail.fromJson(data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingDraft = false);
      } else {
        _loadingDraft = false;
      }
    }
  }

  Future<void> _approve(MenuJob job) async {
    setState(() => _loadingDraft = true);
    try {
      final headers = await _authHeaders();
      final resp = await http.post(
          Uri.parse('$_baseUrl/ingest/${job.id}/approve'),
          headers: headers);
      if (resp.statusCode != 200) {
        throw Exception('Approve failed (${resp.statusCode})');
      }
      if (!mounted) return;
      showShadSnack(context, title: 'Published', type: ShadSnackType.success);
      // Refresh jobs list
      setState(() {
        _jobsFuture = _fetchJobs();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingDraft = false);
      } else {
        _loadingDraft = false;
      }
    }
  }

  Future<void> _loadAgentJobs() async {
    try {
      final headers = await _authHeaders();
      final resp =
          await http.get(Uri.parse('$_baseUrl/agent-jobs'), headers: headers);
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final jobs = (data['jobs'] as List)
          .map((j) => AgentJob.fromJson(Map<String, dynamic>.from(j)))
          .toList();
      setState(() => _agentJobs = jobs);
    } catch (_) {
      // ignore UI errors
    }
  }

  Future<void> _loadAgentConfig() async {
    try {
      final headers = await _authHeaders();
      final resp = await http.get(Uri.parse('$_baseUrl/agent-worker/config'),
          headers: headers);
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      setState(() => _agentEnabled = (data['enabled'] as bool?) ?? false);
    } catch (_) {}
  }

  Future<void> _setAgentEnabled(bool enabled) async {
    setState(() => _agentEnabled = enabled);
    try {
      final headers = await _authHeaders();
      await http.post(Uri.parse('$_baseUrl/agent-worker/config'),
          headers: headers, body: jsonEncode({'enabled': enabled}));
    } catch (_) {}
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
            final jobs = snapshot.data ?? [];
            if (jobs.isEmpty) {
              return const Center(child: Text('No ingestion jobs yet.'));
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _JobsList(
                    jobs: jobs,
                    selected: _selected,
                    onSelect: _loadDraft,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: _DraftPane(
                    loading: _loadingDraft,
                    draft: _draft,
                    error: _error,
                    onApprove:
                        _selected == null ? null : () => _approve(_selected!),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: AgentQueuePane(
                    jobs: _agentJobs,
                    onRefresh: _loadAgentJobs,
                    enabled: _agentEnabled,
                    onToggle: _setAgentEnabled,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Future<Map<String, String>> _authHeaders() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Not signed in');
  final token = await user.getIdToken();
  return {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };
}

class _JobsList extends StatelessWidget {
  const _JobsList(
      {required this.jobs, required this.selected, required this.onSelect});
  final List<MenuJob> jobs;
  final MenuJob? selected;
  final void Function(MenuJob) onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return ShadCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: jobs.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, idx) {
          final job = jobs[idx];
          final isSelected = selected?.id == job.id;
          IconData icon;
          Color color;
          if (job.status == 'ready') {
            icon = Icons.check_circle;
            color = cs.primary;
          } else if (job.status == 'error') {
            icon = Icons.error;
            color = cs.destructive;
          } else {
            icon = Icons.schedule;
            color = cs.mutedForeground;
          }
          return ListTile(
            tileColor: isSelected ? cs.accent.withValues(alpha: 0.08) : null,
            title: Text(job.restaurantId),
            subtitle: Text(
                '${job.id}\n${job.status} • ${DateTime.fromMillisecondsSinceEpoch(job.updatedAt).toLocal()}'),
            isThreeLine: true,
            onTap: () => onSelect(job),
            trailing: Icon(icon, color: color),
          );
        },
      ),
    );
  }
}

class _DraftPane extends StatelessWidget {
  const _DraftPane(
      {required this.loading,
      required this.draft,
      required this.error,
      this.onApprove});
  final bool loading;
  final DraftDetail? draft;
  final String? error;
  final VoidCallback? onApprove;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return ShadAlert.destructive(
        title: const Text('Failed to load draft'),
        description: Text(error!),
      );
    }
    if (draft == null) {
      return const ShadAlert(
        title: Text('Select a job to view draft'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Draft items (${draft!.items.length})',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            if (onApprove != null)
              ShadButton(
                onPressed: onApprove,
                child: const Text('Approve & Publish'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: draft!.fileUrls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, idx) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                draft!.fileUrls[idx],
                fit: BoxFit.contain,
                width: 220,
                height: 160,
              ),
            ),
          ),
        ),
        if (draft!.compositeUrls.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Composite preview',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: draft!.compositeUrls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  draft!.compositeUrls[idx],
                  fit: BoxFit.contain,
                  width: 240,
                  height: 200,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: ShadCard(
            padding: EdgeInsets.zero,
            child: ListView.separated(
              itemCount: draft!.items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, idx) {
                final item = draft!.items[idx];
                final thumb = item.photoUrl ?? item.imageUrl;
                return ListTile(
                  onTap: thumb == null
                      ? null
                      : () => showDialog(
                            context: context,
                            builder: (_) => Dialog(
                              child: InteractiveViewer(
                                child: Image.network(
                                  thumb,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                  leading: thumb != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            thumb,
                            width: 96,
                            height: 96,
                            fit: BoxFit.contain,
                          ),
                        )
                      : const SizedBox(width: 96, height: 96),
                  title: Text(item.name),
                  subtitle: Text(
                      '${item.category ?? 'uncategorized'} • ${item.price != null ? '\$${item.price}' : 'no price'}'),
                  trailing: item.available
                      ? const Icon(Icons.check, color: Colors.green)
                      : const Icon(Icons.pause, color: Colors.orange),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class MenuJob {
  final String id;
  final String restaurantId;
  final String status;
  final int updatedAt;
  MenuJob(
      {required this.id,
      required this.restaurantId,
      required this.status,
      required this.updatedAt});
  factory MenuJob.fromJson(Map<String, dynamic> json) => MenuJob(
        id: json['jobId'] as String,
        restaurantId: json['restaurantId'] as String,
        status: json['status'] as String,
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

class AgentJob {
  AgentJob(
      {required this.id,
      required this.status,
      required this.prompt,
      required this.fileUri,
      required this.updatedAt});
  final String id;
  final String status;
  final String prompt;
  final String fileUri;
  final int updatedAt;

  factory AgentJob.fromJson(Map<String, dynamic> json) => AgentJob(
        id: json['id'] as String,
        status: json['status'] as String,
        prompt: json['prompt'] as String? ?? '',
        fileUri: json['fileUri'] as String? ?? '',
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

class AgentQueuePane extends StatelessWidget {
  const AgentQueuePane(
      {required this.jobs,
      required this.onRefresh,
      required this.enabled,
      required this.onToggle,
      super.key});
  final List<AgentJob> jobs;
  final VoidCallback onRefresh;
  final bool enabled;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            title: const Text('Agent Queue'),
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ShadSwitch(
                  value: enabled,
                  onChanged: onToggle,
                ),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: onRefresh,
                  child: const Icon(Icons.refresh, size: 16),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: jobs.isEmpty
                ? const Center(child: Text('No queued agent jobs.'))
                : ListView.separated(
                    itemCount: jobs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final j = jobs[idx];
                      return ListTile(
                        title: Text(j.status),
                        subtitle: Text(
                            '${j.id}\n${j.prompt}\n${j.fileUri}\n${DateTime.fromMillisecondsSinceEpoch(j.updatedAt).toLocal()}'),
                        isThreeLine: true,
                        dense: true,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class DraftDetail {
  final List<DraftItem> items;
  final List<String> fileUrls;
  final List<String> compositeUrls;
  DraftDetail(
      {required this.items,
      required this.fileUrls,
      required this.compositeUrls});
  factory DraftDetail.fromJson(Map<String, dynamic> json) => DraftDetail(
        items: ((json['draft']?['items'] ?? []) as List)
            .map((e) => DraftItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        fileUrls:
            (json['fileUrls'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        compositeUrls: (json['draft']?['compositeUrls'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

class DraftItem {
  final String name;
  final String? category;
  final num? price;
  final bool available;
  final String? imageUrl;
  final String? photoUrl;
  DraftItem(
      {required this.name,
      this.category,
      this.price,
      required this.available,
      this.imageUrl,
      this.photoUrl});
  factory DraftItem.fromJson(Map<String, dynamic> json) => DraftItem(
        name: json['name']?.toString() ?? 'Unnamed',
        category: json['category'] as String?,
        price: json['price'] as num?,
        available: json['available'] as bool? ?? true,
        imageUrl: json['imageUrl'] as String?,
        photoUrl: json['photoUrl'] as String?,
      );
}
