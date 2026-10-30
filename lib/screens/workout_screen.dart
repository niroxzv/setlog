import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/models/workout_session.dart';
import 'package:flutter_application_mbapproject/providers/firebase_provider.dart';
import 'package:flutter_application_mbapproject/providers/firestore_provider.dart';
import 'package:flutter_application_mbapproject/theme/app_theme.dart';
import 'package:flutter_application_mbapproject/screens/active_workout_screen.dart';
import 'package:flutter_application_mbapproject/screens/session_detail_screen.dart';
import 'package:flutter_application_mbapproject/screens/start_session_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// How many sessions a week the streak card treats as the target.
const int _weeklyGoal = 5;

// Home dashboard: greeting + streak + stats + today's session + recent list.
// Every number is derived from the user's real session documents.
class WorkoutScreen extends ConsumerWidget {
  const WorkoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    // Pull the signed-in user so we can personalise the greeting.
    // Watching authStateProvider means the header rebuilds if displayName changes.
    final AsyncValue<dynamic> auth = ref.watch(authStateProvider);
    final User? user = auth.value as User?;
    final String displayName = _firstName(user);

    // Every session for this user, newest first. The dashboard derives the
    // streak, this week's totals and the Recent list from this one stream
    // rather than issuing three separate queries.
    final AsyncValue<List<WorkoutSession>> sessionsAsync =
        ref.watch(allSessionsProvider);
    final List<WorkoutSession> sessions =
        sessionsAsync.value ?? const <WorkoutSession>[];

    final _WeekSummary week = _WeekSummary.from(sessions);
    // Finished sessions only — the one in progress has its own card above.
    final List<WorkoutSession> recent =
        sessions.where((WorkoutSession s) => !s.isActive).take(3).toList();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: <Widget>[
            _GreetingHeader(displayName: displayName, theme: theme),
            const SizedBox(height: 16),
            _StreakCard(
              streakWeeks: _currentStreak(sessions),
              trainedWeekdays: week.trainedWeekdays,
              theme: theme,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _StatTile(
                    icon: Icons.bolt_outlined,
                    label: 'VOLUME',
                    value: _thousands(week.volumeKg),
                    unit: 'kg this week',
                    theme: theme,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    icon: Icons.access_time,
                    label: 'SESSIONS',
                    value: '${week.sessionCount}',
                    unit: '/ $_weeklyGoal this week',
                    theme: theme,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SectionHeader(title: "Today's session", theme: theme),
            const SizedBox(height: 8),
            _TodaySessionCard(theme: theme),
            const SizedBox(height: 20),
            _SectionHeader(title: 'Recent', theme: theme),
            const SizedBox(height: 4),
            // Inline ListView replacement — Column-of-cards inside the outer
            // ListView. We don't use a nested ListView here because the outer
            // one already handles scrolling.
            if (sessionsAsync.isLoading && sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No finished workouts yet. Your last three sessions will '
                  'show up here.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ...recent.map(
                (WorkoutSession s) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _RecentSessionRow(
                    session: s,
                    theme: theme,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => SessionDetailScreen(sessionId: s.id),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      // FAB — "start a new session" (e.g. Push, Pull, Legs).
      //
      // The tag is explicit because MainScreen hosts the tabs in an
      // IndexedStack, which keeps every tab mounted at once. Two default
      // FloatingActionButtons would then be alive in the same subtree sharing
      // one Hero tag, which Flutter reports as a multiple-heroes exception.
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_start_session',
        onPressed: () => _openStartSessionSheet(context),
        tooltip: 'Start session',
        child: const Icon(Icons.add),
      ),
    );
  }

  String _firstName(User? user) {
    if (user == null || user.isAnonymous) return 'there';
    final String? full = user.displayName?.trim();
    if (full != null && full.isNotEmpty) {
      return full.split(RegExp(r'\s+')).first;
    }
    final String? email = user.email;
    if (email != null && email.contains('@')) {
      return email.split('@').first;
    }
    return 'there';
  }

  // 4320 -> "4,320". Written out rather than pulling in intl for one call.
  String _thousands(double value) {
    final String digits = value.round().toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  // Consecutive weeks, ending with this one, in which at least one session
  // was logged.
  //
  // Counted in weeks rather than days because nobody trains seven days a
  // week — a daily streak breaks on the rest days a sensible programme is
  // built around, which punishes the user for following it. A week is the
  // unit a training split actually repeats on.
  //
  // Walking backwards over a Set of trained weeks keeps this O(streak)
  // rather than O(sessions²).
  int _currentStreak(List<WorkoutSession> sessions) {
    if (sessions.isEmpty) return 0;

    final Set<String> trainedWeeks = sessions
        .map((WorkoutSession s) => _weekKey(s.date))
        .toSet();

    DateTime cursor = _startOfWeek(DateTime.now());

    // Nothing logged yet this week shouldn't wipe out a streak that is still
    // alive — the week isn't over.
    if (!trainedWeeks.contains(_weekKey(cursor))) {
      cursor = _startOfWeek(cursor.subtract(const Duration(days: 7)));
    }

    int streak = 0;
    while (trainedWeeks.contains(_weekKey(cursor))) {
      streak++;
      cursor = _startOfWeek(cursor.subtract(const Duration(days: 7)));
    }
    return streak;
  }

  // The Monday of the week containing [date], normalised to midnight, so a
  // week has one unambiguous identity.
  DateTime _startOfWeek(DateTime date) {
    final DateTime day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  String _weekKey(DateTime date) => _dayKey(_startOfWeek(date));

  void _openStartSessionSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const StartSessionScreen(),
    );
  }
}

// Calendar-day identity, so two DateTimes on the same day compare equal
// regardless of the time component Firestore stored.
String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

// This week's totals, Monday through Sunday.
class _WeekSummary {
  const _WeekSummary({
    required this.sessionCount,
    required this.volumeKg,
    required this.trainedWeekdays,
  });

  final int sessionCount;
  final double volumeKg;

  // 0 = Monday … 6 = Sunday, matching the letters on the streak card.
  final Set<int> trainedWeekdays;

  factory _WeekSummary.from(List<WorkoutSession> sessions) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime monday = today.subtract(Duration(days: today.weekday - 1));

    int count = 0;
    double volume = 0;
    final Set<int> days = <int>{};

    for (final WorkoutSession s in sessions) {
      // isBefore(monday) excludes last week; the upper bound is open-ended so
      // a session logged later today still counts.
      if (s.date.isBefore(monday)) continue;
      count++;
      volume += s.totalVolumeKg;
      days.add(s.date.weekday - 1);
    }

    return _WeekSummary(
      sessionCount: count,
      volumeKg: volume,
      trainedWeekdays: days,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Greeting + avatar header
// ──────────────────────────────────────────────────────────────────────

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.displayName, required this.theme});
  final String displayName;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final String dateLine = _formatDateLine(DateTime.now());

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                dateLine,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_greeting()}, $displayName.',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
        CircleAvatar(
          radius: 22,
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Text(
            displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
            style: TextStyle(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  String _greeting() {
    final int hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String _formatDateLine(DateTime now) {
    const List<String> days = <String>[
      'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY',
      'FRIDAY', 'SATURDAY', 'SUNDAY',
    ];
    const List<String> months = <String>[
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return '${days[now.weekday - 1]} · ${now.day} ${months[now.month - 1]}';
  }
}

// ──────────────────────────────────────────────────────────────────────
// Dark "current streak" card with weekday ticks
// ──────────────────────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  const _StreakCard({
    required this.streakWeeks,
    required this.trainedWeekdays,
    required this.theme,
  });

  final int streakWeeks;
  final Set<int> trainedWeekdays;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final int todayIdx = DateTime.now().weekday - 1; // 0..6 (Mon..Sun)

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // Near-black background like the screenshot — looks premium against
        // the otherwise white surface.
        color: theme.setLog.focusPanel,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.setLog.energy.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.local_fire_department,
                  color: theme.setLog.energy,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Current streak',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Text(
                        '$streakWeeks',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        streakWeeks == 1 ? 'week' : 'weeks',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Each chip flexes to share available width so this row never overflows
          // on narrower viewports.
          Row(
            children: List<Widget>.generate(7, (int i) {
              const List<String> letters = <String>[
                'M', 'T', 'W', 'T', 'F', 'S', 'S',
              ];
              // Ticked when a session was actually logged on that weekday.
              final bool done = trainedWeekdays.contains(i);
              final bool isToday = i == todayIdx;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _DayChip(
                    letter: letters[i],
                    done: done,
                    isToday: isToday && !done,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.letter,
    required this.done,
    required this.isToday,
  });
  final String letter;
  final bool done;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    late final Color bg;
    late final Color fg;
    late final BoxBorder? border;

    if (done) {
      bg = theme.colorScheme.primary;
      fg = theme.colorScheme.onPrimary;
      border = null;
    } else if (isToday) {
      bg = Colors.transparent;
      fg = Colors.white;
      border = Border.all(color: Colors.white54, width: 1.4, strokeAlign: -1);
    } else {
      bg = Colors.white.withValues(alpha: 0.08);
      fg = Colors.white60;
      border = null;
    }

    return Container(
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: border,
      ),
      child: done
          ? Icon(Icons.check, size: 14, color: fg)
          : Text(
              letter,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Square stat tile (Volume / Sessions)
// ──────────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
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
          Icon(icon, color: theme.colorScheme.primary, size: 18),
          const SizedBox(height: 10),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: Text(
                  value,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  unit,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
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
// Section header — "Today's session", "Recent"
// ──────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.theme});

  final String title;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Today's session card with progress bar
// ──────────────────────────────────────────────────────────────────────

// Shows whichever session is currently marked is_active in Firestore, or an
// invitation to start one if there isn't a workout in progress.
class _TodaySessionCard extends ConsumerWidget {
  const _TodaySessionCard({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WorkoutSession? session = ref.watch(activeSessionProvider).value;

    if (session == null) return _buildEmpty(context);

    // Live set count for the session in progress.
    final int setCount =
        ref.watch(sessionSetsProvider(session.id)).value?.length ?? 0;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ActiveWorkoutScreen(sessionId: session.id),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.fitness_center,
                color: theme.colorScheme.onPrimaryContainer,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    session.name,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    setCount == 0
                        ? 'In progress · no sets yet'
                        : 'In progress · $setCount sets logged',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.setLog.category(session.category),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                session.category.name.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // No workout running — nudge the user toward the start-session sheet.
  Widget _buildEmpty(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.self_improvement,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'No session in progress',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap + below to start today\'s workout.',
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

// ──────────────────────────────────────────────────────────────────────
// Recent session row
// ──────────────────────────────────────────────────────────────────────

class _RecentSessionRow extends StatelessWidget {
  const _RecentSessionRow({
    required this.session,
    required this.theme,
    required this.onTap,
  });

  final WorkoutSession session;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.fitness_center,
              size: 18,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  session.name,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${session.setCount} sets · '
                  '${session.totalVolumeKg.toStringAsFixed(0)} kg total',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (session.hasPr)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                Icons.emoji_events,
                size: 16,
                color: theme.colorScheme.primary,
              ),
            ),
          Icon(
            Icons.chevron_right,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      ),
    );
  }
}
