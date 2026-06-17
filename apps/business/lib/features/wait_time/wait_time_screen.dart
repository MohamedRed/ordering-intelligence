import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/wait_time_providers.dart';
import '../../widgets/business_scaffold.dart';
import 'wait_time_daily_card.dart';
import 'wait_time_mode.dart';
import 'wait_time_summary_card.dart';

class WaitTimeScreen extends ConsumerStatefulWidget {
  const WaitTimeScreen({super.key});

  @override
  ConsumerState<WaitTimeScreen> createState() => _WaitTimeScreenState();
}

class _WaitTimeScreenState extends ConsumerState<WaitTimeScreen> {
  WaitTimeMode _mode = WaitTimeMode.overall;

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(waitTimeSummaryProvider);
    final dailyAsync = ref.watch(waitTimeDailyProvider(7));

    return BusinessScaffold(
      title: const Text('Wait time insights'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            ref.invalidate(waitTimeSummaryProvider);
            ref.invalidate(waitTimeDailyProvider(7));
          },
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          WaitTimeSummaryCard(
            summary: summaryAsync,
            onRetry: () => ref.invalidate(waitTimeSummaryProvider),
          ),
          const SizedBox(height: 16),
          WaitTimeDailyCard(
            daily: dailyAsync,
            mode: _mode,
            onModeChanged: (mode) => setState(() => _mode = mode),
            onRetry: () => ref.invalidate(waitTimeDailyProvider(7)),
          ),
        ],
      ),
    );
  }
}
