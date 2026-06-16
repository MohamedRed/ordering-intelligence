import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'menu_ingestion_models.dart';

class MenuJobsList extends StatelessWidget {
  const MenuJobsList({
    required this.jobs,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final List<MenuJob> jobs;
  final MenuJob? selected;
  final void Function(MenuJob) onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return ShadCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: jobs.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No ingestion jobs yet.'),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: jobs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final job = jobs[idx];
                  final isSelected = selected?.id == job.id;
                  final status = _statusPresentation(job.status, cs);
                  return ListTile(
                    tileColor:
                        isSelected ? cs.accent.withValues(alpha: 0.08) : null,
                    title: Text(job.restaurantId),
                    subtitle: Text(
                      '${job.id}\n${job.status} • ${_formatMillis(job.updatedAt)}',
                    ),
                    isThreeLine: true,
                    onTap: () => onSelect(job),
                    trailing: Icon(status.icon, color: status.color),
                  );
                },
              ),
      ),
    );
  }
}

class DraftPane extends StatelessWidget {
  const DraftPane({
    required this.loading,
    required this.draft,
    required this.error,
    this.onApprove,
    super.key,
  });

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
    final detail = draft;
    if (detail == null) {
      return const ShadAlert(title: Text('Select a job to view draft'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Draft items (${detail.items.length})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (onApprove != null)
              ShadButton(
                onPressed: onApprove,
                child: const Text('Approve & Publish'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _ImageStrip(urls: detail.fileUrls, height: 160, width: 220),
        if (detail.compositeUrls.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Composite preview',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _ImageStrip(urls: detail.compositeUrls, height: 200, width: 240),
        ],
        const SizedBox(height: 12),
        SizedBox(
          height: 420,
          child: ShadCard(
            padding: EdgeInsets.zero,
            child: ListView.separated(
              itemCount: detail.items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, idx) => _DraftItemTile(
                item: detail.items[idx],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AgentQueuePane extends StatelessWidget {
  const AgentQueuePane({
    required this.jobs,
    required this.onRefresh,
    required this.enabled,
    required this.onToggle,
    this.error,
    super.key,
  });

  final List<AgentJob> jobs;
  final VoidCallback onRefresh;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            title: const Text('Agent Queue'),
            subtitle: error == null ? null : Text(error!),
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ShadSwitch(value: enabled, onChanged: onToggle),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: onRefresh,
                  child: const Icon(Icons.refresh, size: 16),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 420,
            child: jobs.isEmpty
                ? const Center(child: Text('No queued agent jobs.'))
                : ListView.separated(
                    itemCount: jobs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final job = jobs[idx];
                      return ListTile(
                        title: Text(job.status),
                        subtitle: Text(
                          '${job.id}\n${job.prompt}\n${job.fileUri}\n${_formatMillis(job.updatedAt)}',
                        ),
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

class _DraftItemTile extends StatelessWidget {
  const _DraftItemTile({required this.item});

  final DraftItem item;

  @override
  Widget build(BuildContext context) {
    final thumb = item.photoUrl ?? item.imageUrl;
    return ListTile(
      onTap: thumb == null
          ? null
          : () => showDialog(
                context: context,
                builder: (_) => Dialog(
                  child: InteractiveViewer(
                    child: Image.network(thumb, fit: BoxFit.contain),
                  ),
                ),
              ),
      leading: thumb == null
          ? const SizedBox(width: 96, height: 96)
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                thumb,
                width: 96,
                height: 96,
                fit: BoxFit.contain,
              ),
            ),
      title: Text(item.name),
      subtitle: Text(
        '${item.category ?? 'uncategorized'} • ${item.price != null ? '\$${item.price}' : 'no price'}',
      ),
      trailing: item.available
          ? const Icon(Icons.check, color: Colors.green)
          : const Icon(Icons.pause, color: Colors.orange),
    );
  }
}

class _ImageStrip extends StatelessWidget {
  const _ImageStrip({
    required this.urls,
    required this.height,
    required this.width,
  });

  final List<String> urls;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, idx) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            urls[idx],
            fit: BoxFit.contain,
            width: width,
            height: height,
          ),
        ),
      ),
    );
  }
}

({IconData icon, Color color}) _statusPresentation(
  String status,
  ShadColorScheme cs,
) {
  if (status == 'ready') return (icon: Icons.check_circle, color: cs.primary);
  if (status == 'error') return (icon: Icons.error, color: cs.destructive);
  return (icon: Icons.schedule, color: cs.mutedForeground);
}

String _formatMillis(int millis) {
  if (millis <= 0) return 'unknown';
  return DateTime.fromMillisecondsSinceEpoch(millis).toLocal().toString();
}
