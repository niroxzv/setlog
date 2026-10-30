import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/models/logged_set.dart';
import 'package:flutter_application_mbapproject/models/workout_session.dart';
import 'package:flutter_application_mbapproject/providers/firestore_provider.dart';
import 'package:flutter_application_mbapproject/providers/rest_timer_provider.dart';
import 'package:flutter_application_mbapproject/screens/log_set_screen.dart';
import 'package:flutter_application_mbapproject/screens/workout_complete_screen.dart';
import 'package:flutter_application_mbapproject/widgets/rest_timer_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_application_mbapproject/theme/app_theme.dart';

// The workout currently in progress. Everything on this screen is live
// Firestore data for one session id:
//   • the session document        [CRUD: Select one]
//   • its sets, ordered           [CRUD: Select all, scoped by session]
//   • logging a set               [CRUD: Insert]  — via LogSetScreen
//   • editing a set               [CRUD: Update]  — via LogSetScreen
//   • removing a set / session    [CRUD: Delete]
class ActiveWorkoutScreen extends ConsumerWidget {
  const ActiveWorkoutScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<WorkoutSession?> session =
        ref.watch(sessionDetailProvider(sessionId));
    final AsyncValue<List<LoggedSet>> sets =
        ref.watch(sessionSetsProvider(sessionId));

    final String title = session.value?.name ?? 'Workout';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: sets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load this workout.\n$err',
                textAlign: TextAlign.center),
          ),
        ),
        data: (List<LoggedSet> setList) {
          final _SessionTotals totals = _SessionTotals.from(setList);
          final DateTime? startedAt = _trainingStart(setList, session.value);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: <Widget>[
              _TimerCard(
                title: title,
                startedAt: startedAt,
                totals: totals,
                theme: theme,
              ),
              const SizedBox(height: 12),
              // Additional feature: rest timer. It lives on this screen rather
              // than a separate one so sets can be logged mid-rest.
              const RestTimerCard(),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Sets logged',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${setList.length} total',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (setList.isEmpty)
                _NoSetsYet(theme: theme)
              else
                ..._buildExerciseGroups(context, ref, setList, theme),

              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _openLogSetSheet(
                  context,
                  existingSets: setList,
                ),
                icon: const Icon(Icons.add),
                label: const Text('Log a set'),
              ),

              const SizedBox(height: 16),
              // Delete-session sits alongside Finish so the destructive
              // action is discoverable but visually secondary.
              Row(
                children: <Widget>[
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border:
                          Border.all(color: theme.colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Delete session',
                      iconSize: 20,
                      onPressed: () => _confirmDeleteSession(context, ref),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _confirmFinish(
                        context,
                        ref,
                        startedAt,
                        totals,
                      ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Finish workout'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // When the workout actually began.
  //
  // Deliberately the first logged set, not the moment the session document was
  // created. Creating a session is how you open the screen — you might do it
  // in the changing room, or leave it open while you find a free bench. Timing
  // from the document would bill all of that as training, which is how a
  // session ends up reading 1:12 with nothing lifted.
  static DateTime? _trainingStart(
    List<LoggedSet> sets,
    WorkoutSession? session,
  ) {
    if (sets.isEmpty) return null;

    DateTime? earliest;
    for (final LoggedSet s in sets) {
      final DateTime? created = s.createdAt;
      if (created == null) continue;
      if (earliest == null || created.isBefore(earliest)) earliest = created;
    }

    // created_at is a server timestamp, so it reads back null for the moment
    // between writing a set and the server resolving it. Fall back to the
    // session start rather than blanking the clock mid-workout.
    return earliest ?? session?.date;
  }

  // Sets arrive ordered by set_number; group them under their exercise so
  // the screen reads like a training log.
  List<Widget> _buildExerciseGroups(
    BuildContext context,
    WidgetRef ref,
    List<LoggedSet> sets,
    ThemeData theme,
  ) {
    final Map<String, List<LoggedSet>> byExercise = <String, List<LoggedSet>>{};
    for (final LoggedSet s in sets) {
      byExercise.putIfAbsent(s.exerciseName, () => <LoggedSet>[]).add(s);
    }

    final List<Widget> out = <Widget>[];
    byExercise.forEach((String exercise, List<LoggedSet> group) {
      out.add(_ExerciseCard(
        exerciseName: exercise,
        sets: group,
        theme: theme,
        onTapSet: (LoggedSet s) => _showSetActions(context, ref, s, sets),
      ));
      out.add(const SizedBox(height: 10));
    });
    return out;
  }

  // Opens the Log Set sheet. Passing [editingSet] switches it to edit mode;
  // [existingSets] lets it work out the next set number for whichever
  // exercise ends up selected.
  void _openLogSetSheet(
    BuildContext context, {
    required List<LoggedSet> existingSets,
    LoggedSet? editingSet,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => LogSetScreen(
        sessionId: sessionId,
        existingSets: existingSets,
        editingSet: editingSet,
      ),
    );
  }

  // Bottom sheet shown when a logged set is tapped — Edit or Delete.
  Future<void> _showSetActions(
    BuildContext context,
    WidgetRef ref,
    LoggedSet set,
    List<LoggedSet> allSets,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 8),
            Text(
              '${set.exerciseName} · set ${set.setNumber}',
              style: Theme.of(ctx)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit set'),
              subtitle: const Text('Adjust weight, reps, or RPE'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openLogSetSheet(
                  context,
                  existingSets: allSets,
                  editingSet: set,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete set'),
              subtitle: const Text('Remove this set from the session'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await ref
                    .read(workoutControllerProvider.notifier)
                    .deleteSet(set.id);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Set deleted.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Deletes the session and every set inside it, then leaves the screen.
  Future<void> _confirmDeleteSession(
    BuildContext context,
    WidgetRef ref,
  ) async {
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

    // Deleting the session leaves nothing to rest between, so drop any
    // pending alert rather than letting it fire against a session that is
    // no longer there.
    await ref.read(restTimerProvider.notifier).stop();

    await ref.read(workoutControllerProvider.notifier).deleteSession(sessionId);
    if (!context.mounted) return;

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Session deleted.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Writes the session's final totals back to Firestore [CRUD: Update] and
  // moves on to the summary screen.
  Future<void> _confirmFinish(
    BuildContext context,
    WidgetRef ref,
    DateTime? startedAt,
    _SessionTotals totals,
  ) async {
    if (totals.setCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Log at least one set before finishing.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Finish workout?'),
        content: Text(
          'You logged ${totals.setCount} sets across '
          '${totals.exerciseCount} exercises. '
          'You can\'t add more sets after this.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep going'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Finish'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // The rest alert is booked with AlarmManager, so it outlives this screen
    // and would fire after the workout is already over. Cancel it here.
    await ref.read(restTimerProvider.notifier).stop();

    // Same start the card counted from, so the saved duration matches the
    // number the lifter watched on screen.
    final int elapsed = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inSeconds;

    await ref.read(workoutControllerProvider.notifier).finishSession(
          sessionId: sessionId,
          durationSeconds: elapsed,
          totalVolumeKg: totals.volumeKg,
          setCount: totals.setCount,
          exerciseCount: totals.exerciseCount,
          hasPr: totals.hasPr,
        );

    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutCompleteScreen(sessionId: sessionId),
      ),
    );
  }
}

// Totals derived from the live set list — recomputed on every rebuild so the
// header and the finish dialog always agree with what's on screen.
class _SessionTotals {
  const _SessionTotals({
    required this.setCount,
    required this.exerciseCount,
    required this.volumeKg,
    required this.hasPr,
  });

  final int setCount;
  final int exerciseCount;
  final double volumeKg;
  final bool hasPr;

  factory _SessionTotals.from(List<LoggedSet> sets) {
    double volume = 0;
    bool pr = false;
    final Set<String> exercises = <String>{};

    for (final LoggedSet s in sets) {
      volume += s.volumeKg;
      exercises.add(s.exerciseName);
      if (s.isPersonalBest) pr = true;
    }

    return _SessionTotals(
      setCount: sets.length,
      exerciseCount: exercises.length,
      volumeKg: volume,
      hasPr: pr,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Top timer card
// ──────────────────────────────────────────────────────────────────────

class _TimerCard extends StatefulWidget {
  const _TimerCard({
    required this.title,
    required this.startedAt,
    required this.totals,
    required this.theme,
  });

  final String title;
  final DateTime? startedAt;
  final _SessionTotals totals;
  final ThemeData theme;

  @override
  State<_TimerCard> createState() => _TimerCardState();
}

class _TimerCardState extends State<_TimerCard> {
  // Without this the duration only refreshed when the widget happened to
  // rebuild (i.e. when a set was logged), so the clock looked frozen. A
  // one-second ticker drives it instead.
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _recalculate();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _recalculate());
  }

  // The session start time arrives asynchronously from Firestore, so recompute
  // when the parent hands down a different value.
  @override
  void didUpdateWidget(covariant _TimerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) _recalculate();
  }

  // Always derived from the stored start timestamp rather than counting
  // ticks, so the total stays correct even if the screen was rebuilt or the
  // app was backgrounded.
  void _recalculate() {
    final DateTime? start = widget.startedAt;
    if (start == null) return;
    final Duration next = DateTime.now().difference(start);
    if (!mounted) return;
    setState(() => _elapsed = next.isNegative ? Duration.zero : next);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = widget.theme;
    final _SessionTotals totals = widget.totals;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.setLog.focusPanel,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'In progress',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.white60),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    // Before the first set there is nothing to count, so the
                    // clock reads zero rather than pretending to run.
                    widget.startedAt == null
                        ? '0:00'
                        : formatDuration(_elapsed),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      fontFeatures: <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  Text(
                    widget.startedAt == null
                        ? 'starts on first set'
                        : 'duration',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white60),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              _MiniStat(
                value: '${totals.setCount}',
                label: 'sets',
              ),
              const SizedBox(width: 20),
              _MiniStat(
                value: totals.volumeKg.toStringAsFixed(0),
                label: 'kg volume',
              ),
              const SizedBox(width: 20),
              _MiniStat(
                value: '${totals.exerciseCount}',
                label: 'exercises',
              ),
            ],
          ),
        ],
      ),
    );
  }

}

// mm:ss, rolling over to h:mm:ss past the hour. Shared with the summary
// screen so a finished workout reads exactly the same as the live clock did.
String formatDuration(Duration d) {
  final String mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final String ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (d.inHours > 0) return '${d.inHours}:$mm:$ss';
  return '$mm:$ss';
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Empty state before the first set is logged
// ──────────────────────────────────────────────────────────────────────

class _NoSetsYet extends StatelessWidget {
  const _NoSetsYet({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.fitness_center,
            size: 36,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            'No sets yet',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap "Log a set" below to record your first one.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// One exercise and its sets, each row tappable for Edit / Delete
// ──────────────────────────────────────────────────────────────────────

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.exerciseName,
    required this.sets,
    required this.theme,
    required this.onTapSet,
  });

  final String exerciseName;
  final List<LoggedSet> sets;
  final ThemeData theme;
  final ValueChanged<LoggedSet> onTapSet;

  @override
  Widget build(BuildContext context) {
    final double volume = sets.fold<double>(
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
                '${sets.length} sets · ${volume.toStringAsFixed(0)} kg',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...sets.map(
            (LoggedSet s) => InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onTapSet(s),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${s.setNumber}',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${s.weightKg.toStringAsFixed(1)} kg × ${s.reps} reps',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (s.rpe != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          'RPE ${s.rpe!.toStringAsFixed(1)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
