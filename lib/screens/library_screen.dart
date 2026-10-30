import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/models/exercise.dart';
import 'package:flutter_application_mbapproject/models/logged_set.dart';
import 'package:flutter_application_mbapproject/providers/firestore_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The exercise catalogue, read live from the `exercises` collection.
//
// Two different kinds of filtering are deliberately shown side by side:
//   • the muscle-group chips swap the Firestore query   [QUERY-1, server-side]
//   • the search box narrows the loaded list in Dart    (Firestore has no
//     "contains" operator, so substring search has to happen client-side)
//
// The screen also covers [CRUD: Select all], [CRUD: Insert] via the add
// button and [CRUD: Delete] via the detail sheet.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  // Matches the categories the seed data writes, plus anything a user adds.
  static const List<String> _categories = <String>[
    'chest',
    'back',
    'legs',
    'shoulders',
    'arms',
    'core',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<Exercise>> exercises =
        ref.watch(libraryExercisesProvider);
    final String? activeCategory = ref.watch(exerciseCategoryFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      floatingActionButton: FloatingActionButton.extended(
        // Unique tag — see the note on the Workout tab's FAB.
        heroTag: 'fab_add_exercise',
        onPressed: () => _openAddExerciseDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add exercise'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: TextField(
              controller: _searchController,
              onChanged: (String v) => setState(() => _query = v.trim()),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search exercises',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _CategoryChips(
            categories: _categories,
            active: activeCategory,
            onSelected: (String? c) =>
                ref.read(exerciseCategoryFilterProvider.notifier).state = c,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: exercises.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object err, _) => _Message(
                icon: Icons.cloud_off,
                title: 'Could not load the library',
                body: '$err',
              ),
              data: (List<Exercise> all) {
                // Client-side substring match on top of the server-side chip.
                final List<Exercise> visible = _query.isEmpty
                    ? all
                    : all
                        .where((Exercise e) =>
                            e.name.toLowerCase().contains(_query.toLowerCase()) ||
                            e.muscleGroup
                                .toLowerCase()
                                .contains(_query.toLowerCase()))
                        .toList();

                if (visible.isEmpty) {
                  return _Message(
                    icon: Icons.fitness_center,
                    title: all.isEmpty
                        ? 'Your library is empty'
                        : 'No matches for "$_query"',
                    body: all.isEmpty
                        ? 'Load the sample data from Profile, or tap '
                            '"Add exercise" to create your own.'
                        : 'Try a different search term or clear the filter.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                  itemCount: visible.length + 1,
                  separatorBuilder: (BuildContext _, int _) =>
                      const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    // Row 0 is the count header so it scrolls with the list.
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${visible.length} exercise'
                          '${visible.length == 1 ? '' : 's'}'
                          '${activeCategory != null ? ' in $activeCategory' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    final Exercise e = visible[index - 1];
                    return _ExerciseRow(
                      exercise: e,
                      onTap: () => _openExerciseSheet(context, e),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Exercise detail — personal-best history for one movement
  // ────────────────────────────────────────────────────────────────

  void _openExerciseSheet(BuildContext context, Exercise exercise) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ExerciseDetailSheet(exercise: exercise),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Create a custom exercise  [CRUD: Insert]
  // ────────────────────────────────────────────────────────────────

  Future<void> _openAddExerciseDialog(BuildContext context) async {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final TextEditingController nameController = TextEditingController();
    final TextEditingController muscleController = TextEditingController();
    final TextEditingController brandController = TextEditingController();
    String category = 'chest';
    String equipment = 'machine';

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setDialogState) {
          // Brand only makes sense for machines, so it's disabled otherwise.
          final bool brandEnabled = equipment == 'machine';

          return AlertDialog(
            title: const Text('New exercise'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextFormField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Exercise name',
                        hintText: 'e.g. Incline Dumbbell Press',
                      ),
                      validator: (String? v) {
                        final String s = (v ?? '').trim();
                        if (s.isEmpty) return 'Give the exercise a name';
                        if (s.length < 3) return 'Name is too short';
                        if (s.length > 40) return 'Keep it under 40 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration:
                          const InputDecoration(labelText: 'Muscle group'),
                      items: _categories
                          .map((String c) => DropdownMenuItem<String>(
                                value: c,
                                child: Text(c),
                              ))
                          .toList(),
                      onChanged: (String? v) =>
                          setDialogState(() => category = v ?? 'chest'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: equipment,
                      decoration:
                          const InputDecoration(labelText: 'Equipment type'),
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(
                            value: 'machine', child: Text('Machine')),
                        DropdownMenuItem<String>(
                            value: 'free_weight', child: Text('Free weight')),
                        DropdownMenuItem<String>(
                            value: 'cable', child: Text('Cable')),
                        DropdownMenuItem<String>(
                            value: 'bodyweight', child: Text('Bodyweight')),
                      ],
                      onChanged: (String? v) =>
                          setDialogState(() => equipment = v ?? 'machine'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: brandController,
                      enabled: brandEnabled,
                      decoration: InputDecoration(
                        labelText: 'Brand',
                        hintText: brandEnabled
                            ? 'e.g. Hammer Strength'
                            : 'Machines only',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: muscleController,
                      decoration: const InputDecoration(
                        labelText: 'Target muscle (optional)',
                        hintText: 'e.g. upper chest',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.of(ctx).pop(true);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true) {
      await ref.read(workoutControllerProvider.notifier).addExercise(
            name: nameController.text.trim(),
            category: category,
            equipmentType: equipment,
            brand: equipment == 'machine' && brandController.text.trim().isNotEmpty
                ? brandController.text.trim()
                : null,
            muscleGroup: muscleController.text.trim(),
          );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${nameController.text.trim()}" added to your library.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    nameController.dispose();
    muscleController.dispose();
    brandController.dispose();
  }
}

// ──────────────────────────────────────────────────────────────────────
// Muscle-group chips — each one re-runs the Firestore query
// ──────────────────────────────────────────────────────────────────────

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.active,
    required this.onSelected,
  });

  final List<String> categories;
  final String? active;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: <Widget>[
          _chip(context, label: 'All', value: null),
          ...categories.map(
            (String c) => _chip(context, label: c, value: c),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context,
      {required String label, required String? value}) {
    final bool selected = active == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(value),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// One row in the catalogue
// ──────────────────────────────────────────────────────────────────────

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise, required this.onTap});

  final Exercise exercise;
  final VoidCallback onTap;

  // Stored values are snake_case; make them readable.
  String get _equipmentLabel {
    switch (exercise.equipmentType) {
      case 'free_weight':
        return 'Free weight';
      case 'plate_loaded':
        return 'Plate loaded';
      case 'bodyweight':
        return 'Bodyweight';
      case 'cable':
        return 'Cable';
      case 'machine':
        return 'Machine';
      default:
        return exercise.equipmentType;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
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
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          exercise.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (exercise.isCustom) ...<Widget>[
                        const SizedBox(width: 6),
                        _MiniTag(
                          label: 'CUSTOM',
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    <String>[
                      exercise.category,
                      _equipmentLabel,
                      if (exercise.brand != null && exercise.brand!.isNotEmpty)
                        exercise.brand!,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Detail sheet — every set ever logged for this exercise, heaviest first
// ──────────────────────────────────────────────────────────────────────

class _ExerciseDetailSheet extends ConsumerWidget {
  const _ExerciseDetailSheet({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<LoggedSet>> history =
        ref.watch(exerciseHistoryProvider(exercise.id));

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    exercise.name,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                // Only user-created entries can be removed — the seeded
                // catalogue is shared.
                if (exercise.isCustom)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Delete exercise',
                    onPressed: () => _confirmDelete(context, ref),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              <String>[
                exercise.category,
                if (exercise.muscleGroup.isNotEmpty) exercise.muscleGroup,
                if (exercise.brand != null && exercise.brand!.isNotEmpty)
                  exercise.brand!,
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Your best sets',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Every set you have logged for this exercise, heaviest first.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            history.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (Object err, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Could not load history.\n$err',
                    style: theme.textTheme.bodySmall),
              ),
              data: (List<LoggedSet> sets) {
                if (sets.isEmpty) {
                  return _Message(
                    icon: Icons.history,
                    title: 'No sets logged yet',
                    body: 'Log this exercise in a workout and your best sets '
                        'will show up here.',
                  );
                }
                return Column(
                  children: <Widget>[
                    _BestRow(best: sets.first, theme: theme),
                    const SizedBox(height: 12),
                    ...sets.take(15).map(
                          (LoggedSet s) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    '${s.weightKg.toStringAsFixed(1)} kg × '
                                    '${s.reps} reps',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (s.rpe != null)
                                  Text(
                                    'RPE ${s.rpe!.toStringAsFixed(1)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                const SizedBox(width: 10),
                                Text(
                                  '${s.volumeKg.toStringAsFixed(0)} kg',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Delete "${exercise.name}"?'),
        content: const Text(
          'This removes the exercise from your library. Sets you already '
          'logged with it are kept.',
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

    await ref
        .read(firestoreServiceProvider)
        .deleteExercise(exercise.id);

    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${exercise.name}" deleted.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// Highlighted card for the single heaviest set.
class _BestRow extends StatelessWidget {
  const _BestRow({required this.best, required this.theme});
  final LoggedSet best;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.emoji_events,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Personal best',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                Text(
                  '${best.weightKg.toStringAsFixed(1)} kg × ${best.reps} reps',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
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

// Shared empty / error placeholder.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              body,
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
