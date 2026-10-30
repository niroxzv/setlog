import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/models/logged_set.dart';
import 'package:flutter_application_mbapproject/models/workout_session.dart';
import 'package:flutter_application_mbapproject/providers/firestore_provider.dart';
import 'package:flutter_application_mbapproject/theme/app_theme.dart';
import 'package:flutter_application_mbapproject/widgets/ai_coach_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Full detail for one past session — opened by tapping a History row.
//
// Reads two things from Firestore:
//   • the session document itself      [CRUD: Select one]
//   • every set belonging to it        [CRUD: Select all, scoped by session]
// and offers                            [CRUD: Delete]
class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<WorkoutSession?> session =
        ref.watch(sessionDetailProvider(sessionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session detail'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Delete session',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load this session.\n$err',
                textAlign: TextAlign.center),
          ),
        ),
        data: (WorkoutSession? s) {
          // The document can legitimately be gone if it was just deleted.
          if (s == null) {
            return const Center(child: Text('This session no longer exists.'));
          }
          return _DetailBody(session: s, theme: theme);
        },
      ),
    );
  }

  // AlertDialog confirm, then a cascading delete of the session and its sets.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Delete this session?'),
        content: const Text(
          'This permanently removes the session and every set logged in it. '
          'You can\'t undo this action.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await ref.read(workoutControllerProvider.notifier).deleteSession(sessionId);
    if (!context.mounted) return;

    final AsyncValue<void> result = ref.read(workoutControllerProvider);
    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: ${result.error}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Session deleted.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.session, required this.theme});

  final WorkoutSession session;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LoggedSet>> sets =
        ref.watch(sessionSetsProvider(session.id));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: <Widget>[
        _SummaryCard(session: session, theme: theme),

        // The same Applied AI analysis the completion screen offers, reachable
        // again from History and Recent. Without this the coach is a one-shot:
        // leave the post-workout screen and that session's advice is gone for
        // good, which is the wrong shape for something you'd want to re-read
        // before repeating the same workout.
        //
        // Hidden on sessions with no sets, where there is nothing to analyse.
        if ((sets.value ?? const <LoggedSet>[]).isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          AiCoachCard(sessionId: session.id),
        ],

        const SizedBox(height: 20),
        Text(
          'Sets logged',
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        sets.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (Object err, _) => Text('Could not load sets: $err'),
          data: (List<LoggedSet> list) {
            if (list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No sets were logged in this session.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }
            return Column(children: _buildGroupedSets(list));
          },
        ),
      ],
    );
  }

  // Sets come back ordered by set_number; group them under their exercise so
  // the screen reads like a training log rather than a flat list.
  List<Widget> _buildGroupedSets(List<LoggedSet> sets) {
    final Map<String, List<LoggedSet>> byExercise = <String, List<LoggedSet>>{};
    for (final LoggedSet s in sets) {
      byExercise.putIfAbsent(s.exerciseName, () => <LoggedSet>[]).add(s);
    }

    final List<Widget> out = <Widget>[];
    byExercise.forEach((String exercise, List<LoggedSet> group) {
      out.add(_ExerciseGroup(
        exerciseName: exercise,
        sets: group,
        theme: theme,
      ));
      out.add(const SizedBox(height: 10));
    });
    return out;
  }
}

// ──────────────────────────────────────────────────────────────────────
// Top summary card — date, duration, volume, counts
// ──────────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.session, required this.theme});
  final WorkoutSession session;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: theme.setLog.category(session.category),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              if (session.hasPr)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.setLog.successContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'PR',
                    style: TextStyle(
                      color: theme.setLog.onSuccessContainer,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formatDate(session.date),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer
                  .withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: _Metric(
                  value: _formatDuration(session.durationSeconds),
                  label: 'Duration',
                  theme: theme,
                ),
              ),
              Expanded(
                child: _Metric(
                  value: '${session.totalVolumeKg.toStringAsFixed(0)} kg',
                  label: 'Volume',
                  theme: theme,
                ),
              ),
              Expanded(
                child: _Metric(
                  value: '${session.setCount}',
                  label: 'Sets',
                  theme: theme,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final String hh = d.hour.toString().padLeft(2, '0');
    final String mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year} · $hh:$mm';
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '—';
    final int mins = seconds ~/ 60;
    return '$mins min';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    required this.theme,
  });

  final String value;
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer
                .withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// One exercise and all of its sets
// ──────────────────────────────────────────────────────────────────────

class _ExerciseGroup extends StatelessWidget {
  const _ExerciseGroup({
    required this.exerciseName,
    required this.sets,
    required this.theme,
  });

  final String exerciseName;
  final List<LoggedSet> sets;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final double groupVolume = sets.fold<double>(
      0,
      (double sum, LoggedSet s) => sum + s.volumeKg,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  exerciseName,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${sets.length} sets · ${groupVolume.toStringAsFixed(0)} kg',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...sets.map((LoggedSet s) => _SetRow(set: s, theme: theme)),
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({required this.set, required this.theme});
  final LoggedSet set;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: set.isPersonalBest
                  ? theme.setLog.success
                  : theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${set.setNumber}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: set.isPersonalBest
                    ? Colors.white
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${set.weightKg.toStringAsFixed(1)} kg × ${set.reps} reps',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (set.rpe != null)
            Text(
              'RPE ${set.rpe!.toStringAsFixed(1)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
