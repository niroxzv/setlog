import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/models/workout_session.dart';
import 'package:flutter_application_mbapproject/providers/firestore_provider.dart';
import 'package:flutter_application_mbapproject/screens/active_workout_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Bottom-sheet form for starting a new workout session.
// Validates the inputs, writes the session document to Firestore
// [CRUD: Insert], then routes into the active workout screen using the new
// document's id.
class StartSessionScreen extends ConsumerStatefulWidget {
  const StartSessionScreen({super.key});

  @override
  ConsumerState<StartSessionScreen> createState() => _StartSessionScreenState();
}

class _StartSessionScreenState extends ConsumerState<StartSessionScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController =
      TextEditingController(text: 'Push A');

  // Workout type drives both the session name suggestion and the category
  // stored in Firestore, which is what the History filter chips query on.
  static const List<String> _workoutTypes = <String>[
    'Push',
    'Pull',
    'Legs',
    'Upper',
    'Lower',
    'Full body',
    'Custom',
  ];
  String? _selectedType = 'Push';

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // Only Push / Pull / Legs map onto a real category; everything else is
  // stored as `other` so the enum can never receive an unexpected value.
  SessionCategory _categoryForType(String type) {
    switch (type) {
      case 'Push':
        return SessionCategory.push;
      case 'Pull':
        return SessionCategory.pull;
      case 'Legs':
        return SessionCategory.legs;
      default:
        return SessionCategory.other;
    }
  }

  Future<void> _handleStart() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedType == null) {
      _showSnackBar('Pick a workout type first.');
      return;
    }

    final String? sessionId =
        await ref.read(workoutControllerProvider.notifier).startSession(
              name: _nameController.text.trim(),
              category: _categoryForType(_selectedType!),
            );

    if (!mounted) return;

    if (sessionId == null) {
      final AsyncValue<void> result = ref.read(workoutControllerProvider);
      _showSnackBar('Could not start session. ${result.error ?? ''}');
      return;
    }

    // Close the sheet, then open the workout we just created.
    Navigator.of(context).pop();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ActiveWorkoutScreen(sessionId: sessionId),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isLoading = ref.watch(workoutControllerProvider).isLoading;

    // Keyboard inset so the sheet floats above the keyboard when the
    // name field is focused.
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Drag handle so users know this sheet is dismissable.
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
              Text(
                'Start a session',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Pick a split and give today\'s session a name.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _buildTypeDropdown(),
              const SizedBox(height: 12),
              _buildNameField(),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: isLoading ? null : _handleStart,
                icon: isLoading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(isLoading ? 'Starting…' : 'Start session'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed:
                    isLoading ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedType,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Workout type',
        prefixIcon: Icon(Icons.category_outlined),
      ),
      items: _workoutTypes
          .map((String t) => DropdownMenuItem<String>(value: t, child: Text(t)))
          .toList(),
      onChanged: (String? value) {
        setState(() {
          _selectedType = value;
          // Suggest a matching name so the user rarely has to type.
          if (value != null) _nameController.text = '$value A';
        });
      },
      validator: (String? value) =>
          value == null ? 'Pick a workout type' : null,
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      // "name" keyboard surfaces the alphabetic layout (no number row).
      keyboardType: TextInputType.name,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _handleStart(),
      decoration: const InputDecoration(
        labelText: 'Session name',
        hintText: 'e.g. Push A',
        prefixIcon: Icon(Icons.edit_outlined),
      ),
      validator: (String? value) {
        final String v = (value ?? '').trim();
        if (v.isEmpty) return 'Give the session a name';
        if (v.length < 2) return 'Name is too short';
        if (v.length > 40) return 'Keep it under 40 characters';
        return null;
      },
    );
  }
}
