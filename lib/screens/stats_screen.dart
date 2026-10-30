import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_mbapproject/models/logged_set.dart';
import 'package:flutter_application_mbapproject/models/stats_range.dart';
import 'package:flutter_application_mbapproject/models/workout_session.dart';
import 'package:flutter_application_mbapproject/providers/firestore_provider.dart';
import 'package:flutter_application_mbapproject/screens/muscle_activation_screen.dart';
import 'package:flutter_application_mbapproject/screens/session_detail_screen.dart';
import 'package:flutter_application_mbapproject/services/firestore_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_application_mbapproject/theme/app_theme.dart';

// Progress overview. Reads three ways on purpose:
//
//   • the all-time totals run Firestore count() / sum() / average() on the
//     server and return only the numbers          [QUERY-5: aggregation]
//   • the volume chart, calendar and split are derived from the session
//     stream                                       [CRUD: Select all]
//   • top lifts come from a two-field filtered query on `sets`  [QUERY-3]
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  StatsRange _range = StatsRange.fourWeeks;
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<WorkoutSession>> sessionsAsync =
        ref.watch(allSessionsProvider);
    final AsyncValue<List<LoggedSet>> prs = ref.watch(recentPrsProvider);
    final AsyncValue<WorkoutStats> stats = ref.watch(workoutStatsProvider);

    final List<WorkoutSession> sessions =
        sessionsAsync.value ?? const <WorkoutSession>[];

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(workoutStatsProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: <Widget>[
              _Header(
                range: _range,
                onRangeChanged: (StatsRange r) => setState(() => _range = r),
                theme: theme,
              ),
              const SizedBox(height: 12),
              _MuscleActivationButton(range: _range, theme: theme),
              const SizedBox(height: 12),

              if (sessionsAsync.isLoading && sessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...<Widget>[
                _VolumeChartCard(
                  sessions: sessions,
                  range: _range,
                  theme: theme,
                ),
                const SizedBox(height: 12),
                _CalendarCard(
                  month: _visibleMonth,
                  sessions: sessions,
                  onPrevious: () => _shiftMonth(-1),
                  onNext: () => _shiftMonth(1),
                  onDayTapped: (List<WorkoutSession> d) => _openDay(context, d),
                  theme: theme,
                ),
                const SizedBox(height: 12),
                _TrainingSplitCard(
                  sessions: sessions,
                  range: _range,
                  theme: theme,
                ),
                const SizedBox(height: 12),
                _AllTimeCard(stats: stats, theme: theme),
                const SizedBox(height: 20),
                Text(
                  'Top lifts',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _TopLifts(prs: prs, theme: theme),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDay(
    BuildContext context,
    List<WorkoutSession> daysSessions,
  ) async {
    if (daysSessions.isEmpty) return;

    if (daysSessions.length == 1) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => SessionDetailScreen(sessionId: daysSessions.first.id),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: daysSessions
              .map((WorkoutSession s) => ListTile(
                    leading: const Icon(Icons.fitness_center),
                    title: Text(s.name),
                    subtitle: Text(
                      '${s.setCount} sets · '
                      '${s.totalVolumeKg.toStringAsFixed(0)} kg',
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => SessionDetailScreen(sessionId: s.id),
                        ),
                      );
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Header — "YOUR DATA / Progress" + range selector
// ──────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.range,
    required this.onRangeChanged,
    required this.theme,
  });

  final StatsRange range;
  final ValueChanged<StatsRange> onRangeChanged;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'YOUR DATA',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Progress',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        // Segmented range picker, sized to sit on the headline's baseline.
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: StatsRange.values.map((StatsRange r) {
              final bool selected = r == range;
              return GestureDetector(
                onTap: () => onRangeChanged(r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? theme.colorScheme.surface : null,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    r.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Entry point into the muscle map
// ──────────────────────────────────────────────────────────────────────

// Carries the currently selected range through, so the map opens on the same
// window the rest of the screen is showing.
class _MuscleActivationButton extends StatelessWidget {
  const _MuscleActivationButton({required this.range, required this.theme});

  final StatsRange range;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MuscleActivationScreen(range: range),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: theme.setLog.focusPanel,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.accessibility_new,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Muscle activation',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'See which muscles you actually worked',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Volume bar chart
// ──────────────────────────────────────────────────────────────────────

class _Bucket {
  const _Bucket({required this.label, required this.volumeKg});
  final String label;
  final double volumeKg;
}

class _VolumeChartCard extends StatelessWidget {
  const _VolumeChartCard({
    required this.sessions,
    required this.range,
    required this.theme,
  });

  final List<WorkoutSession> sessions;
  final StatsRange range;
  final ThemeData theme;

  static const List<String> _shortMonths = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  // Buckets run oldest -> newest so the last bar is the current period.
  List<_Bucket> _buildBuckets() {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final List<_Bucket> out = <_Bucket>[];

    if (range.isWeekly) {
      final DateTime thisMonday =
          today.subtract(Duration(days: today.weekday - 1));
      for (int i = range.buckets - 1; i >= 0; i--) {
        final DateTime start = thisMonday.subtract(Duration(days: 7 * i));
        final DateTime end = start.add(const Duration(days: 7));
        final double volume = sessions
            .where((WorkoutSession s) =>
                !s.date.isBefore(start) && s.date.isBefore(end))
            .fold<double>(
                0, (double sum, WorkoutSession s) => sum + s.totalVolumeKg);
        out.add(_Bucket(
          label: '${_shortMonths[start.month - 1]} ${start.day}',
          volumeKg: volume,
        ));
      }
    } else {
      for (int i = range.buckets - 1; i >= 0; i--) {
        final DateTime start = DateTime(now.year, now.month - i);
        final DateTime end = DateTime(now.year, now.month - i + 1);
        final double volume = sessions
            .where((WorkoutSession s) =>
                !s.date.isBefore(start) && s.date.isBefore(end))
            .fold<double>(
                0, (double sum, WorkoutSession s) => sum + s.totalVolumeKg);
        out.add(_Bucket(
          label: _shortMonths[start.month - 1],
          volumeKg: volume,
        ));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final List<_Bucket> buckets = _buildBuckets();
    final double peak = buckets.fold<double>(
      0,
      (double m, _Bucket b) => b.volumeKg > m ? b.volumeKg : m,
    );

    final double current = buckets.isEmpty ? 0 : buckets.last.volumeKg;
    final double previous =
        buckets.length >= 2 ? buckets[buckets.length - 2].volumeKg : 0;

    // Percentage change against the previous period. Undefined when there was
    // no previous volume to compare against.
    final double? changePercent =
        previous > 0 ? ((current - previous) / previous) * 100 : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  range.isWeekly ? 'Weekly volume' : 'Monthly volume',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    // Tonnes reads better than five-digit kilogram totals.
                    '${(current / 1000).toStringAsFixed(1)}t',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Row(
                    children: <Widget>[
                      Text(
                        range.isWeekly ? 'this week' : 'this month',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (changePercent != null) ...<Widget>[
                        const SizedBox(width: 4),
                        Icon(
                          changePercent >= 0
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 10,
                          color: changePercent >= 0
                              ? theme.setLog.success
                              : theme.colorScheme.error,
                        ),
                        Text(
                          '${changePercent.abs().toStringAsFixed(0)}%',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: changePercent >= 0
                                ? theme.setLog.success
                                : theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Bars are plain Containers with a proportional height — no chart
          // package needed for four values.
          //
          // The bar area is Expanded and the height is expressed as a
          // fraction of it, so the label always gets the room it needs. Giving
          // the bars a fixed pixel height instead overflows the moment the
          // label's font metrics or the device text scale change.
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: buckets.map((_Bucket b) {
                final bool isCurrent = b == buckets.last;
                // Guard against divide-by-zero when nothing has been logged.
                final double fraction = peak <= 0 ? 0.0 : b.volumeKg / peak;
                // Floor of 0.08 keeps an empty period visible as a flat bar
                // rather than as nothing at all.
                final double heightFactor =
                    (0.08 + (0.92 * fraction)).clamp(0.08, 1.0);

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: heightFactor,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? theme.colorScheme.primary
                                      : theme
                                          .colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          b.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: isCurrent
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Training calendar — the proposal's additional feature
// ──────────────────────────────────────────────────────────────────────

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.month,
    required this.sessions,
    required this.onPrevious,
    required this.onNext,
    required this.onDayTapped,
    required this.theme,
  });

  final DateTime month;
  final List<WorkoutSession> sessions;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<List<WorkoutSession>> onDayTapped;
  final ThemeData theme;

  static const List<String> _monthNames = <String>[
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    final Map<int, List<WorkoutSession>> byDay = <int, List<WorkoutSession>>{};
    for (final WorkoutSession s in sessions) {
      if (s.date.year == month.year && s.date.month == month.month) {
        byDay.putIfAbsent(s.date.day, () => <WorkoutSession>[]).add(s);
      }
    }

    final DateTime now = DateTime.now();
    final bool showingCurrentMonth =
        now.year == month.year && now.month == month.month;

    // Day 0 of next month == last day of this one.
    final int daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // weekday is 1=Mon..7=Sun and the grid starts on Monday.
    final int leadingBlanks = DateTime(month.year, month.month, 1).weekday - 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Training calendar · ${_monthNames[month.month - 1]}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: 'Previous month',
                onPressed: onPrevious,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: 'Next month',
                onPressed: onNext,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: <Widget>[
              Expanded(child: _WeekdayLabel('M')),
              Expanded(child: _WeekdayLabel('T')),
              Expanded(child: _WeekdayLabel('W')),
              Expanded(child: _WeekdayLabel('T')),
              Expanded(child: _WeekdayLabel('F')),
              Expanded(child: _WeekdayLabel('S')),
              Expanded(child: _WeekdayLabel('S')),
            ],
          ),
          const SizedBox(height: 4),
          ..._buildWeekRows(
            daysInMonth: daysInMonth,
            leadingBlanks: leadingBlanks,
            byDay: byDay,
            todayDay: showingCurrentMonth ? now.day : -1,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              _LegendSwatch(color: theme.colorScheme.primary),
              const SizedBox(width: 5),
              Text(
                'Training',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              _LegendSwatch(color: theme.colorScheme.surfaceContainerHighest),
              const SizedBox(width: 5),
              Text(
                'Rest',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildWeekRows({
    required int daysInMonth,
    required int leadingBlanks,
    required Map<int, List<WorkoutSession>> byDay,
    required int todayDay,
  }) {
    final List<Widget> cells = <Widget>[];
    for (int i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (int day = 1; day <= daysInMonth; day++) {
      final List<WorkoutSession> daysSessions =
          byDay[day] ?? const <WorkoutSession>[];
      cells.add(_DayCell(
        day: day,
        sessions: daysSessions,
        isToday: day == todayDay,
        theme: theme,
        onTap: daysSessions.isEmpty ? null : () => onDayTapped(daysSessions),
      ));
    }
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }

    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < cells.length; i += 7) {
      rows.add(Row(
        children: cells
            .sublist(i, i + 7)
            .map((Widget c) => Expanded(child: c))
            .toList(),
      ));
    }
    return rows;
  }
}

// Rounded square rather than a circle, matching the mockup's block calendar.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.sessions,
    required this.isToday,
    required this.theme,
    required this.onTap,
  });

  final int day;
  final List<WorkoutSession> sessions;
  final bool isToday;
  final ThemeData theme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool trained = sessions.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(2.5),
      child: AspectRatio(
        aspectRatio: 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Tooltip(
            message: trained
                ? sessions.map((WorkoutSession s) => s.name).join(', ')
                : '',
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: trained
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
                border: isToday
                    ? Border.all(
                        color: theme.colorScheme.onSurface, width: 1.5)
                    : null,
              ),
              child: Text(
                '$day',
                style: TextStyle(
                  color: trained
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight:
                      trained || isToday ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Training split — share of sessions per category
// ──────────────────────────────────────────────────────────────────────

class _TrainingSplitCard extends StatelessWidget {
  const _TrainingSplitCard({
    required this.sessions,
    required this.range,
    required this.theme,
  });

  final List<WorkoutSession> sessions;
  final StatsRange range;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final DateTime cutoff = range.cutoff;
    final List<WorkoutSession> window = sessions
        .where((WorkoutSession s) => !s.date.isBefore(cutoff))
        .toList();

    final Map<SessionCategory, int> counts = <SessionCategory, int>{};
    for (final WorkoutSession s in window) {
      counts[s.category] = (counts[s.category] ?? 0) + 1;
    }

    // Fixed ordering so the bars don't jump around between rebuilds.
    final List<SessionCategory> ordered = <SessionCategory>[
      SessionCategory.push,
      SessionCategory.pull,
      SessionCategory.legs,
      SessionCategory.other,
    ].where((SessionCategory c) => (counts[c] ?? 0) > 0).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Training split (${range.windowLabel})',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (ordered.isEmpty)
            Text(
              'No sessions in this window yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...ordered.map((SessionCategory c) {
              final int count = counts[c]!;
              final double share = count / window.length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            _categoryLabel(c),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                        Text(
                          '$count session${count == 1 ? '' : 's'}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 34,
                          child: Text(
                            '${(share * 100).round()}%',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: share,
                        minHeight: 6,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _categoryColour(c),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  String _categoryLabel(SessionCategory c) {
    switch (c) {
      case SessionCategory.push:
        return 'Push';
      case SessionCategory.pull:
        return 'Pull';
      case SessionCategory.legs:
        return 'Legs';
      case SessionCategory.other:
        return 'Other';
    }
  }

  Color _categoryColour(SessionCategory c) {
    switch (c) {
      case SessionCategory.push:
        return theme.colorScheme.primary;
      case SessionCategory.pull:
        return theme.setLog.success;
      case SessionCategory.legs:
        return theme.setLog.energy;
      case SessionCategory.other:
        return theme.colorScheme.outline;
    }
  }
}

// ──────────────────────────────────────────────────────────────────────
// All-time totals — the server-side aggregation
// ──────────────────────────────────────────────────────────────────────

class _AllTimeCard extends ConsumerWidget {
  const _AllTimeCard({required this.stats, required this.theme});

  final AsyncValue<WorkoutStats> stats;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'All time',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                'server-side totals',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          stats.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
            // Compact, actionable error instead of dumping the raw exception.
            error: (Object err, _) => _IndexErrorCard(
              error: err,
              title: 'Totals need a Firestore index',
              explanation: 'sum() and average() combined with a filter need a '
                  'composite index on sessions. Copy the link below, open it '
                  'in a browser to create the index, then retry.',
              onRetry: () => ref.invalidate(workoutStatsProvider),
              theme: theme,
            ),
            data: (WorkoutStats s) => Row(
              children: <Widget>[
                Expanded(
                  child: _MiniStat(
                    value: _thousands(s.totalVolumeKg),
                    unit: 'kg',
                    label: 'Volume',
                    theme: theme,
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    value: '${s.sessionCount}',
                    unit: '',
                    label: 'Sessions',
                    theme: theme,
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    value: s.averageDurationSeconds > 0
                        ? '${(s.averageDurationSeconds / 60).round()}'
                        : '—',
                    unit: s.averageDurationSeconds > 0 ? 'min' : '',
                    label: 'Avg session',
                    theme: theme,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _thousands(double value) {
    final String digits = value.round().toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}

// Firestore raises failed-precondition when a query needs a composite index
// that doesn't exist yet, and embeds a console link that creates it with the
// right fields pre-filled. Digging that link out of the exception and putting
// it on the clipboard is far more use than printing the whole stack.
class _IndexErrorCard extends StatelessWidget {
  const _IndexErrorCard({
    required this.error,
    required this.title,
    required this.explanation,
    required this.theme,
    this.onRetry,
  });

  final Object error;
  final String title;
  final String explanation;
  final ThemeData theme;
  final VoidCallback? onRetry;

  static final RegExp _linkPattern =
      RegExp(r'https://console\.firebase\.google\.com/\S+');

  bool get _isMissingIndex =>
      error.toString().contains('failed-precondition') ||
      error.toString().contains('requires an index');

  // The message repeats the URL, and the trailing copy can pick up a stray
  // bracket from the exception's own formatting — take the first, cleaned.
  String? get _consoleLink {
    final RegExpMatch? m = _linkPattern.firstMatch(error.toString());
    if (m == null) return null;
    return m.group(0)!.replaceAll(RegExp(r'[,)\]}]+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final String? link = _consoleLink;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _isMissingIndex ? title : 'Something went wrong',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isMissingIndex ? explanation : '$error',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isMissingIndex && link != null) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Copy console link'),
                    onPressed: () => _copy(context, link),
                  ),
                ),
                if (onRetry != null) ...<Widget>[
                  const SizedBox(width: 8),
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ],
            ),
          ] else if (onRetry != null) ...<Widget>[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onRetry, child: const Text('Retry')),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copied — open it in a browser to create the index.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.value,
    required this.unit,
    required this.label,
    required this.theme,
  });

  final String value;
  final String unit;
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            if (unit.isNotEmpty) ...<Widget>[
              const SizedBox(width: 3),
              Text(
                unit,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Top lifts
// ──────────────────────────────────────────────────────────────────────

class _TopLifts extends StatelessWidget {
  const _TopLifts({required this.prs, required this.theme});

  final AsyncValue<List<LoggedSet>> prs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return prs.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object err, _) => _IndexErrorCard(
        error: err,
        title: 'Top lifts need a Firestore index',
        explanation: 'This query filters sets on user_id and '
            'is_personal_best, then sorts by created_at. Copy the link below '
            'and open it in a browser to create the index.',
        theme: theme,
      ),
      data: (List<LoggedSet> list) {
        if (list.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: _cardDecoration(theme),
            child: Text(
              'No personal records yet. Beat a previous weight on any exercise '
              'and it will show up here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        // One row per exercise — keep only that exercise's heaviest PB.
        final Map<String, LoggedSet> best = <String, LoggedSet>{};
        for (final LoggedSet s in list) {
          final LoggedSet? current = best[s.exerciseName];
          if (current == null || s.weightKg > current.weightKg) {
            best[s.exerciseName] = s;
          }
        }

        return Column(
          children: best.values
              .map((LoggedSet s) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _TopLiftRow(set: s, theme: theme),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _TopLiftRow extends StatelessWidget {
  const _TopLiftRow({required this.set, required this.theme});

  final LoggedSet set;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: _cardDecoration(theme),
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
                Text(
                  set.exerciseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Best set · ${set.reps} reps'
                  '${set.rpe != null ? ' @ RPE ${set.rpe!.toStringAsFixed(1)}' : ''}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                set.weightKg.toStringAsFixed(1),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 3),
              Text(
                'kg',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
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
// Shared bits
// ──────────────────────────────────────────────────────────────────────

BoxDecoration _cardDecoration(ThemeData theme) {
  return BoxDecoration(
    color: theme.colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: theme.colorScheme.outlineVariant),
  );
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
