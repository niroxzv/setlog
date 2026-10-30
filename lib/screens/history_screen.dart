import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/models/workout_session.dart';
import 'package:flutter_application_mbapproject/providers/firestore_provider.dart';
import 'package:flutter_application_mbapproject/screens/session_detail_screen.dart';
import 'package:flutter_application_mbapproject/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Past workout sessions, read live from Firestore.
//
// Two different kinds of filtering happen here on purpose:
//   • the category chips change the Firestore query itself (server-side),
//     because Firestore can index and filter on `category` for us;
//   • the search box filters the list already in memory (client-side),
//     because Firestore has no substring/contains operator.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // Select all + sort, or one of the filtered variants when a chip is
    // active — see sessionsProvider for which query each chip runs.
    final AsyncValue<List<WorkoutSession>> sessions =
        ref.watch(sessionsProvider);
    final HistoryFilter activeFilter = ref.watch(sessionFilterProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 8),
              Text(
                'History',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                // Count comes straight from the live query result.
                sessions.when(
                  data: (List<WorkoutSession> list) =>
                      '${list.length} sessions logged',
                  loading: () => 'Loading sessions…',
                  error: (_, _) => 'Could not load sessions',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _SearchField(
                controller: _searchController,
                theme: theme,
                onChanged: (String value) => setState(() => _search = value),
              ),
              const SizedBox(height: 12),
              _FilterChipRow(
                selected: activeFilter,
                onChanged: (HistoryFilter filter) {
                  // Writing to the provider re-runs the Firestore query.
                  ref.read(sessionFilterProvider.notifier).state = filter;
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: sessions.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (Object err, _) => _ErrorState(
                    message: err.toString(),
                    theme: theme,
                  ),
                  data: (List<WorkoutSession> list) {
                    final List<WorkoutSession> visible = _applySearch(list);
                    if (visible.isEmpty) {
                      return _EmptyState(
                        theme: theme,
                        isSearching: _search.trim().isNotEmpty,
                        isFiltered: activeFilter != HistoryFilter.all,
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (BuildContext context, int index) {
                        return _SessionRow(
                          session: visible[index],
                          theme: theme,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Client-side name match. Firestore can't do "contains", so this runs over
  // the documents the query already returned.
  List<WorkoutSession> _applySearch(List<WorkoutSession> list) {
    final String q = _search.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list
        .where((WorkoutSession s) => s.name.toLowerCase().contains(q))
        .toList();
  }
}

// ──────────────────────────────────────────────────────────────────────
// Search field
// ──────────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.theme,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ThemeData theme;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search sessions…',
        prefixIcon: const Icon(Icons.search),
        // Clear button only appears once there's something to clear.
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHigh,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Filter chips: All / Push / Pull / Legs
// ──────────────────────────────────────────────────────────────────────

class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow({required this.selected, required this.onChanged});

  final HistoryFilter selected;
  final ValueChanged<HistoryFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: HistoryFilter.values.map((HistoryFilter filter) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _FilterChip(
              label: filter.label,
              active: filter == selected,
              onTap: () => onChanged(filter),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.black : Colors.transparent,
          border: Border.all(
            color: active ? Colors.black : theme.colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Empty / error states — feedback beyond SnackBar and AlertDialog
// ──────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.theme,
    required this.isSearching,
    required this.isFiltered,
  });

  final ThemeData theme;
  final bool isSearching;
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    late final String title;
    late final String subtitle;

    if (isSearching) {
      title = 'No matching sessions';
      subtitle = 'Try a different search term.';
    } else if (isFiltered) {
      title = 'Nothing in this category yet';
      subtitle = 'Switch back to All, or log a session of this type.';
    } else {
      title = 'No sessions yet';
      subtitle = 'Start a workout from the Workout tab and it\'ll show here.';
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.fitness_center,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.theme});
  final String message;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_off,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Couldn\'t load your sessions',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// One session row: date pill | title/subtitle | category dot + chevron
// ──────────────────────────────────────────────────────────────────────

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.theme});
  final WorkoutSession session;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      // Tapping opens the Select-one detail screen.
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => SessionDetailScreen(sessionId: session.id),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: <Widget>[
            _DatePill(date: session.date, theme: theme),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          session.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (session.hasPr) ...<Widget>[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
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
                    '${session.exerciseCount} exercises · '
                    '${session.setCount} sets · '
                    '${_formatVolume(session.totalVolumeKg)} kg',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: theme.setLog.category(session.category),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // 4320 -> "4,320" with a thousands separator.
  String _formatVolume(double kg) {
    final String raw = kg.toStringAsFixed(0);
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      if (i > 0 && (raw.length - i) % 3 == 0) out.write(',');
      out.write(raw[i]);
    }
    return out.toString();
  }
}

// ──────────────────────────────────────────────────────────────────────
// Left-side date pill: weekday / big day number (or TODAY) / month
// ──────────────────────────────────────────────────────────────────────

class _DatePill extends StatelessWidget {
  const _DatePill({required this.date, required this.theme});
  final DateTime date;
  final ThemeData theme;

  static const List<String> _weekdays = <String>[
    'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN',
  ];
  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final bool isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;

    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          Text(
            _weekdays[date.weekday - 1],
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          if (isToday)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'TODAY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            )
          else
            Text(
              '${date.day}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          const SizedBox(height: 2),
          Text(
            _months[date.month - 1],
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
