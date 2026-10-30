import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/models/logged_set.dart';
import 'package:flutter_application_mbapproject/models/workout_session.dart';
import 'package:flutter_application_mbapproject/providers/firebase_provider.dart';
import 'package:flutter_application_mbapproject/providers/firestore_provider.dart';
import 'package:flutter_application_mbapproject/screens/active_workout_screen.dart'
    show formatDuration;
import 'package:flutter_application_mbapproject/widgets/ai_coach_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_application_mbapproject/theme/app_theme.dart';

// Shown when the user taps "Finish workout". Every number here is read back
// from Firestore for this session id, so the summary reflects what was
// actually saved rather than what was on screen.
class WorkoutCompleteScreen extends ConsumerWidget {
  const WorkoutCompleteScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    // Pull the user's first name for the personal greeting in the subtitle.
    final AsyncValue<dynamic> auth = ref.watch(authStateProvider);
    final User? user = auth.value as User?;
    final String firstName = _firstName(user);

    final WorkoutSession? session =
        ref.watch(sessionDetailProvider(sessionId)).value;
    final List<LoggedSet> sets =
        ref.watch(sessionSetsProvider(sessionId)).value ?? const <LoggedSet>[];

    final double volume =
        sets.fold<double>(0, (double sum, LoggedSet s) => sum + s.volumeKg);
    final List<LoggedSet> prSets =
        sets.where((LoggedSet s) => s.isPersonalBest).toList();

    // Group by exercise so the breakdown lists one row per movement.
    final Map<String, List<LoggedSet>> byExercise = <String, List<LoggedSet>>{};
    for (final LoggedSet s in sets) {
      byExercise.putIfAbsent(s.exerciseName, () => <LoggedSet>[]).add(s);
    }

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: const Text('Workout summary'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: <Widget>[
          _HeroHeader(
            firstName: firstName,
            sessionName: session?.name ?? 'Workout',
            durationSeconds: session?.durationSeconds ?? 0,
            theme: theme,
          ),
          const SizedBox(height: 20),
          // Row + Column combo for the 3-up stats grid.
          Row(
            children: <Widget>[
              Expanded(
                child: _StatPill(
                  icon: Icons.format_list_numbered,
                  value: '${sets.length}',
                  label: 'Total sets',
                  theme: theme,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatPill(
                  icon: Icons.bolt_outlined,
                  value: volume.toStringAsFixed(0),
                  label: 'Volume (kg)',
                  theme: theme,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatPill(
                  icon: Icons.emoji_events_outlined,
                  value: '${prSets.length}',
                  label: 'PRs hit',
                  theme: theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Only celebrate a PR if one was actually set.
          if (prSets.isNotEmpty) ...<Widget>[
            _PrCard(prSet: prSets.first, theme: theme),
            const SizedBox(height: 16),
          ],
          Text(
            'Exercise breakdown',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ...byExercise.entries.map(
            (MapEntry<String, List<LoggedSet>> entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ExerciseBreakdownRow(
                name: entry.key,
                isPr: entry.value.any((LoggedSet s) => s.isPersonalBest),
                sets: entry.value.length,
                volumeKg: entry.value.fold<double>(
                  0,
                  (double sum, LoggedSet s) => sum + s.volumeKg,
                ),
                theme: theme,
              ),
            ),
          ),
          const SizedBox(height: 16),
          AiCoachCard(sessionId: sessionId),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              // pop back to whichever screen launched the workout flow.
              Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String _firstName(User? user) {
    if (user == null || user.isAnonymous) return 'there';
    final String? full = user.displayName?.trim();
    if (full != null && full.isNotEmpty) {
      return _capitalise(full.split(RegExp(r'\s+')).first);
    }
    final String? email = user.email;
    if (email != null && email.contains('@')) {
      // Email local parts are lower-case, so "toh@..." would greet the user
      // as "toh" without this.
      return _capitalise(email.split('@').first);
    }
    return 'there';
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ──────────────────────────────────────────────────────────────────────
// Big blue header with the success tick + headline + timer
// ──────────────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.firstName,
    required this.sessionName,
    required this.durationSeconds,
    required this.theme,
  });

  final String firstName;
  final String sessionName;
  final int durationSeconds;
  final ThemeData theme;

  // Reuses the live timer's formatter so the summary shows the same value the
  // clock was showing the moment "Finish workout" was tapped.
  String get _duration {
    if (durationSeconds <= 0) return '--:--';
    return formatDuration(Duration(seconds: durationSeconds));
  }

  // Label under the big number changes with the magnitude of the duration.
  String get _durationUnit => durationSeconds >= 3600 ? 'hours' : 'min';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.onPrimary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check,
              size: 36,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$sessionName complete!',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Great work, $firstName.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                _duration,
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _durationUnit,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Stat pill used 3 times in the row
// ──────────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.value,
    required this.label,
    required this.theme,
  });

  final IconData icon;
  final String value;
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// "New personal record!" card
// ──────────────────────────────────────────────────────────────────────

class _PrCard extends StatelessWidget {
  const _PrCard({required this.prSet, required this.theme});
  final LoggedSet prSet;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.setLog.successContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.setLog.successContainer),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.setLog.success,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.emoji_events,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'New personal record!',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: theme.setLog.onSuccessContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${prSet.exerciseName} · '
                  '${prSet.weightKg.toStringAsFixed(1)} kg × ${prSet.reps} reps',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.setLog.onSuccessContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// One row in the exercise breakdown list
// ──────────────────────────────────────────────────────────────────────

class _ExerciseBreakdownRow extends StatelessWidget {
  const _ExerciseBreakdownRow({
    required this.name,
    required this.isPr,
    required this.sets,
    required this.volumeKg,
    required this.theme,
  });

  final String name;
  final bool isPr;
  final int sets;
  final double volumeKg;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.fitness_center,
              size: 16,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (isPr) ...<Widget>[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.setLog.successContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'PR',
                          style: TextStyle(
                            color: theme.setLog.onSuccessContainer,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$sets sets · Volume ${volumeKg.toStringAsFixed(0)} kg',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

