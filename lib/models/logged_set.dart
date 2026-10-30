import 'package:cloud_firestore/cloud_firestore.dart';

// One logged set — the `sets` collection from the Part 1 data dictionary.
// Kept as a top-level collection (not a subcollection of sessions) so we can
// query every set of a given exercise across all sessions, which is what
// powers the personal-best history.
class LoggedSet {
  const LoggedSet({
    required this.id,
    required this.userId,
    required this.sessionId,
    required this.exerciseId,
    required this.exerciseName,
    required this.setNumber,
    required this.weightKg,
    required this.reps,
    this.rpe,
    this.isPersonalBest = false,
    this.notes = '',
    this.createdAt,
  });

  final String id;
  final String userId;
  final String sessionId;
  final String exerciseId;
  final String exerciseName; // denormalised so set rows render without a join
  final int setNumber;
  final double weightKg;
  final int reps;
  final double? rpe; // 1.0-10.0 in 0.5 steps, nullable per the dictionary
  final bool isPersonalBest;
  final String notes;
  final DateTime? createdAt;

  // Volume is the standard training metric: weight x reps.
  double get volumeKg => weightKg * reps;

  factory LoggedSet.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return LoggedSet(
      id: doc.id,
      userId: d['user_id'] as String? ?? '',
      sessionId: d['session_id'] as String? ?? '',
      exerciseId: d['exercise_id'] as String? ?? '',
      exerciseName: d['exercise_name'] as String? ?? '',
      setNumber: d['set_number'] as int? ?? 1,
      weightKg: (d['weight_kg'] as num?)?.toDouble() ?? 0,
      reps: d['reps'] as int? ?? 0,
      rpe: (d['rpe'] as num?)?.toDouble(),
      isPersonalBest: d['is_personal_best'] as bool? ?? false,
      notes: d['notes'] as String? ?? '',
      createdAt: (d['created_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'user_id': userId,
      'session_id': sessionId,
      'exercise_id': exerciseId,
      'exercise_name': exerciseName,
      'set_number': setNumber,
      'weight_kg': weightKg,
      'reps': reps,
      'rpe': rpe,
      'is_personal_best': isPersonalBest,
      'notes': notes,
      'created_at': FieldValue.serverTimestamp(),
    };
  }
}
