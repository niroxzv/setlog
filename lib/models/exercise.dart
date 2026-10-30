import 'package:cloud_firestore/cloud_firestore.dart';

// Mirrors the `exercises` table from the Part 1 data dictionary.
// Firestore field names are kept in snake_case so a marker can open the
// console and see exactly the fields listed in the proposal.
//
// user_id is null for the pre-seeded catalogue and set for exercises the
// user created themselves (is_custom == true).
class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.category,
    required this.equipmentType,
    this.userId,
    this.brand,
    this.muscleGroup = '',
    this.isCustom = false,
    this.timesLogged = 0,
    this.bestWeightKg,
    this.bestReps,
  });

  final String id;
  final String? userId;
  final String name;
  final String category; // chest, back, legs, shoulders, arms, core
  final String equipmentType; // machine, free_weight, plate_loaded, cable...
  final String? brand; // only meaningful when equipmentType == machine
  final String muscleGroup;
  final bool isCustom;
  final int timesLogged;
  final double? bestWeightKg;
  final int? bestReps;

  factory Exercise.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return Exercise(
      id: doc.id,
      userId: d['user_id'] as String?,
      name: d['name'] as String? ?? '',
      category: d['exercise_category'] as String? ?? 'other',
      equipmentType: d['equipment_type'] as String? ?? 'other',
      brand: d['brand'] as String?,
      muscleGroup: d['muscle_group'] as String? ?? '',
      isCustom: d['is_custom'] as bool? ?? false,
      timesLogged: d['times_logged'] as int? ?? 0,
      // Firestore returns num for numeric fields — cast defensively.
      bestWeightKg: (d['best_weight_kg'] as num?)?.toDouble(),
      bestReps: d['best_reps'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'user_id': userId,
      'name': name,
      'exercise_category': category,
      'equipment_type': equipmentType,
      'brand': brand,
      'muscle_group': muscleGroup,
      'is_custom': isCustom,
      'times_logged': timesLogged,
      'best_weight_kg': bestWeightKg,
      'best_reps': bestReps,
      'created_at': FieldValue.serverTimestamp(),
    };
  }
}
