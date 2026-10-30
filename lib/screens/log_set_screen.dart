import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/models/exercise.dart';
import 'package:flutter_application_mbapproject/models/logged_set.dart';
import 'package:flutter_application_mbapproject/providers/firestore_provider.dart';
import 'package:flutter_application_mbapproject/providers/rest_timer_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Bottom-sheet form for logging or editing sets.
//
//   editingSet == null  ->  [CRUD: Insert] one or more new sets
//   editingSet != null  ->  [CRUD: Update] that single existing set
//
// The exercise list is read live from Firestore, and a new exercise can be
// created inline with its equipment type and brand — the distinction the
// proposal is built around, since two machines can be identical apart from
// the manufacturer.
class LogSetScreen extends ConsumerStatefulWidget {
  const LogSetScreen({
    super.key,
    required this.sessionId,
    required this.existingSets,
    this.editingSet,
  });

  final String sessionId;
  final List<LoggedSet> existingSets;
  final LoggedSet? editingSet;

  bool get isEditing => editingSet != null;

  @override
  ConsumerState<LogSetScreen> createState() => _LogSetScreenState();
}

class _LogSetScreenState extends ConsumerState<LogSetScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _weightController;

  // Selected exercise document id. Null until the library loads.
  String? _exerciseId;
  late int _sets;
  late int _reps;
  late double _rpe;

  @override
  void initState() {
    super.initState();
    final LoggedSet? editing = widget.editingSet;
    _exerciseId = editing?.exerciseId;
    _weightController = TextEditingController(
      text: (editing?.weightKg ?? 20).toStringAsFixed(1),
    );
    // Editing always targets exactly one set.
    _sets = 1;
    _reps = editing?.reps ?? 8;
    _rpe = editing?.rpe ?? 8.0;
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  // Next ordinal for this exercise within this session, so set numbers read
  // 1, 2, 3 per exercise rather than across the whole workout.
  int _nextSetNumber(String exerciseId) {
    final int used = widget.existingSets
        .where((LoggedSet s) => s.exerciseId == exerciseId)
        .length;
    return used + 1;
  }

  Future<void> _handleSave(List<Exercise> library) async {
    if (!_formKey.currentState!.validate()) return;
    if (_exerciseId == null) {
      _showSnackBar('Pick an exercise first.');
      return;
    }

    final double weight = double.parse(_weightController.text.trim());
    final Exercise exercise = library.firstWhere(
      (Exercise e) => e.id == _exerciseId,
      orElse: () => const Exercise(
        id: '',
        name: 'Exercise',
        category: 'other',
        equipmentType: 'other',
      ),
    );

    final WorkoutController controller =
        ref.read(workoutControllerProvider.notifier);

    if (widget.isEditing) {
      await controller.updateSet(
        setId: widget.editingSet!.id,
        weightKg: weight,
        reps: _reps,
        rpe: _rpe,
      );
    } else {
      // The Sets counter lets the user record several identical sets at
      // once; each becomes its own document with a running set number.
      final int start = _nextSetNumber(_exerciseId!);
      for (int i = 0; i < _sets; i++) {
        await controller.logSet(
          sessionId: widget.sessionId,
          exerciseId: _exerciseId!,
          exerciseName: exercise.name,
          setNumber: start + i,
          weightKg: weight,
          reps: _reps,
          rpe: _rpe,
        );
      }
    }

    if (!mounted) return;

    final AsyncValue<void> result = ref.read(workoutControllerProvider);
    if (result.hasError) {
      _showSnackBar('Could not save: ${result.error}');
      return;
    }

    // Saving a new set starts the rest countdown automatically, which is the
    // behaviour the proposal describes. Editing an existing set is a
    // correction, not a set just performed, so it doesn't trigger rest.
    if (!widget.isEditing) {
      await ref
          .read(restTimerProvider.notifier)
          .start(exerciseName: exercise.name);
    }

    if (!mounted) return;

    Navigator.of(context).pop();
    _showSnackBar(
      widget.isEditing
          ? 'Set ${widget.editingSet!.setNumber} updated.'
          : '${_sets == 1 ? 'Set' : '$_sets sets'} logged for ${exercise.name}.'
              ' Rest timer started.',
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // Bumps the weight and writes it back into the TextFormField.
  void _bumpWeight(double delta) {
    final double current =
        double.tryParse(_weightController.text.trim()) ?? 0.0;
    final double next = (current + delta).clamp(0.0, 500.0);
    setState(() {
      _weightController.text = next.toStringAsFixed(1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final AsyncValue<List<Exercise>> library = ref.watch(exercisesProvider);
    final bool isSaving = ref.watch(workoutControllerProvider).isLoading;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                widget.isEditing ? 'EDITING SET' : 'LOGGING EXERCISE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.isEditing
                    ? 'Edit set ${widget.editingSet!.setNumber}'
                    : 'Log a Set',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),

              _SectionLabel('Exercise', theme: theme),
              const SizedBox(height: 6),
              library.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
                error: (Object err, _) => Text(
                  'Could not load exercises: $err',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                data: (List<Exercise> list) =>
                    _buildExerciseSection(list, theme),
              ),

              const SizedBox(height: 16),
              _SectionLabel('Weight', theme: theme),
              const SizedBox(height: 6),
              _buildWeightRow(theme),
              const SizedBox(height: 8),
              _buildIncrementButtons(theme),

              const SizedBox(height: 16),
              _SectionLabel('Volume', theme: theme),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  // Editing targets one set, so the Sets counter is hidden.
                  if (!widget.isEditing) ...<Widget>[
                    Expanded(
                      child: _CounterField(
                        label: 'SETS',
                        value: _sets,
                        onChanged: (int v) => setState(() => _sets = v),
                        theme: theme,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: _CounterField(
                      label: 'REPS',
                      value: _reps,
                      onChanged: (int v) => setState(() => _reps = v),
                      theme: theme,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              _SectionLabel('Effort (RPE)', theme: theme),
              _buildRpeSlider(theme),

              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () => _handleSave(library.value ?? <Exercise>[]),
                child: isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(widget.isEditing ? 'Update set' : 'Save set'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Exercise picker plus a read-only summary of the selected exercise's
  // equipment type and brand, and a shortcut to create a new one.
  Widget _buildExerciseSection(List<Exercise> list, ThemeData theme) {
    if (list.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'No exercises yet.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _openNewExerciseDialog,
            icon: const Icon(Icons.add),
            label: const Text('Create an exercise'),
          ),
        ],
      );
    }

    // Fall back to the first exercise until the user picks one.
    final Exercise selected = list.firstWhere(
      (Exercise e) => e.id == _exerciseId,
      orElse: () => list.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DropdownButtonFormField<String>(
          initialValue: selected.id,
          isExpanded: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.fitness_center),
            labelText: 'Exercise name',
          ),
          items: list
              .map((Exercise e) => DropdownMenuItem<String>(
                    value: e.id,
                    child: Text(e.name, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (String? value) => setState(() => _exerciseId = value),
          validator: (String? value) =>
              value == null ? 'Pick an exercise' : null,
        ),
        const SizedBox(height: 8),
        // equipment_type and brand belong to the exercise, not the set, so
        // they're shown here as context rather than as editable fields.
        Row(
          children: <Widget>[
            _InfoChip(
              icon: Icons.settings_outlined,
              label: selected.equipmentType.replaceAll('_', ' '),
              theme: theme,
            ),
            const SizedBox(width: 8),
            if (selected.brand != null && selected.brand!.isNotEmpty)
              _InfoChip(
                icon: Icons.business_outlined,
                label: selected.brand!,
                theme: theme,
              ),
            const Spacer(),
            TextButton.icon(
              onPressed: _openNewExerciseDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New'),
            ),
          ],
        ),
      ],
    );
  }

  // Creates a custom exercise [CRUD: Insert] with the equipment type and
  // brand fields from the proposal's data dictionary.
  Future<void> _openNewExerciseDialog() async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController brandController = TextEditingController();
    final GlobalKey<FormState> dialogKey = GlobalKey<FormState>();
    String category = 'chest';
    String equipment = 'machine';

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setDialogState) {
          return AlertDialog(
            title: const Text('New exercise'),
            content: Form(
              key: dialogKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextFormField(
                    controller: nameController,
                    keyboardType: TextInputType.name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (String? v) {
                      final String s = (v ?? '').trim();
                      if (s.isEmpty) return 'Name is required';
                      if (s.length < 3) return 'Name is too short';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration:
                        const InputDecoration(labelText: 'Muscle group'),
                    items: const <String>[
                      'chest', 'back', 'legs', 'shoulders', 'arms', 'core',
                    ]
                        .map((String c) =>
                            DropdownMenuItem<String>(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (String? v) =>
                        setDialogState(() => category = v ?? 'chest'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: equipment,
                    decoration:
                        const InputDecoration(labelText: 'Equipment type'),
                    items: const <String>[
                      'machine',
                      'free_weight',
                      'plate_loaded',
                      'cable',
                      'bodyweight',
                      'other',
                    ]
                        .map((String c) => DropdownMenuItem<String>(
                            value: c, child: Text(c.replaceAll('_', ' '))))
                        .toList(),
                    onChanged: (String? v) =>
                        setDialogState(() => equipment = v ?? 'machine'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: brandController,
                    keyboardType: TextInputType.name,
                    // Brand only matters for machines, matching the data
                    // dictionary where it is nullable for free weights.
                    enabled: equipment == 'machine',
                    decoration: InputDecoration(
                      labelText: 'Brand',
                      hintText: equipment == 'machine'
                          ? 'e.g. Technogym'
                          : 'Machines only',
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (!dialogKey.currentState!.validate()) return;
                  Navigator.of(ctx).pop(true);
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true) {
      nameController.dispose();
      brandController.dispose();
      return;
    }

    await ref.read(workoutControllerProvider.notifier).addExercise(
          name: nameController.text.trim(),
          category: category,
          equipmentType: equipment,
          brand:
              equipment == 'machine' && brandController.text.trim().isNotEmpty
                  ? brandController.text.trim()
                  : null,
          muscleGroup: category,
        );

    nameController.dispose();
    brandController.dispose();

    if (!mounted) return;
    _showSnackBar('Exercise created.');
  }

  // [-] [82.5] [+] weight stepper. Stays a TextFormField so typed values
  // still go through validation.
  Widget _buildWeightRow(ThemeData theme) {
    return Row(
      children: <Widget>[
        _RoundIconButton(
          icon: Icons.remove,
          onPressed: () => _bumpWeight(-2.5),
          theme: theme,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: _weightController,
            textAlign: TextAlign.center,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              hintText: '0',
              suffixText: 'kg',
            ),
            validator: (String? value) {
              final String v = (value ?? '').trim();
              if (v.isEmpty) return 'Required';
              final double? n = double.tryParse(v);
              if (n == null) return 'Number only';
              // 0 is valid — bodyweight exercises like pull ups.
              if (n < 0) return 'Cannot be negative';
              if (n > 500) return 'Too heavy';
              return null;
            },
          ),
        ),
        const SizedBox(width: 10),
        _RoundIconButton(
          icon: Icons.add,
          onPressed: () => _bumpWeight(2.5),
          theme: theme,
        ),
      ],
    );
  }

  // Plate-style quick-add buttons.
  Widget _buildIncrementButtons(ThemeData theme) {
    const List<double> increments = <double>[1.25, 2.5, 5, 10];
    return Row(
      children: increments
          .map(
            (double v) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: OutlinedButton(
                  onPressed: () => _bumpWeight(v),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(36),
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    '+${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildRpeSlider(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              _rpe.toStringAsFixed(1),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            Text(
              _rpeLabel(_rpe),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        // divisions: (10 - 1) / 0.5 = 18 steps.
        Slider(
          value: _rpe,
          min: 1,
          max: 10,
          divisions: 18,
          label: _rpe.toStringAsFixed(1),
          onChanged: (double v) => setState(() => _rpe = v),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '1 Easy',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '10 Max',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _rpeLabel(double rpe) {
    if (rpe <= 4) return 'Easy';
    if (rpe <= 6) return 'Moderate';
    if (rpe <= 8) return 'Hard';
    return 'Max effort';
  }
}

// ──────────────────────────────────────────────────────────────────────
// Small reusable building blocks
// ──────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.theme});
  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 1.0,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onPressed,
    required this.theme,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onPressed,
      radius: 28,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: theme.colorScheme.onSurface),
      ),
    );
  }
}

// Counter for sets / reps with -/+ buttons around the value.
class _CounterField extends StatelessWidget {
  const _CounterField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.theme,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              _RoundIconButton(
                icon: Icons.remove,
                onPressed: () => onChanged((value - 1).clamp(1, 99)),
                theme: theme,
              ),
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              _RoundIconButton(
                icon: Icons.add,
                onPressed: () => onChanged((value + 1).clamp(1, 99)),
                theme: theme,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
