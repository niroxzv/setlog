import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_mbapproject/models/workout_session.dart';

// Writes a realistic starter dataset into Firestore for the signed-in user:
// an exercise library plus several past sessions with all of their sets.
//
// This exists so the app has meaningful records to read on a fresh account,
// and so the database can be reset to a known state before a demo. Everything
// is written through a single WriteBatch, which is atomic and counts as one
// round trip instead of ~100.
class SeedService {
  SeedService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // One exercise in the seeded library. Mirrors the proposal's point that
  // two machines can be identical apart from the brand.
  static const List<(String, String, String, String?)> _exercises =
      <(String, String, String, String?)>[
    // (name, category, equipment_type, brand)
    ('Bench Press', 'chest', 'free_weight', null),
    ('Incline DB Press', 'chest', 'free_weight', null),
    ('Chest Press', 'chest', 'machine', 'Technogym'),
    ('Cable Fly', 'chest', 'cable', null),
    ('Lat Pulldown', 'back', 'machine', 'Life Fitness'),
    ('Barbell Row', 'back', 'free_weight', null),
    ('Seated Row', 'back', 'machine', 'Cybex'),
    ('Pull Up', 'back', 'bodyweight', null),
    ('Squat', 'legs', 'free_weight', null),
    ('Leg Press', 'legs', 'plate_loaded', 'Hammer Strength'),
    ('Romanian Deadlift', 'legs', 'free_weight', null),
    ('Leg Extension', 'legs', 'machine', 'Technogym'),
    ('Overhead Press', 'shoulders', 'free_weight', null),
    ('Lateral Raise', 'shoulders', 'free_weight', null),
    ('Bicep Curl', 'arms', 'free_weight', null),
    ('Tricep Pushdown', 'arms', 'cable', null),
  ];

  // Session blueprints: name, category, how many days ago it happened,
  // duration in minutes, and the exercises performed with their working
  // weight, reps and RPE. Weights climb slightly in the more recent
  // sessions so the progressive-overload story in Stats looks real.
  static const List<_SeedSession> _sessions = <_SeedSession>[
    _SeedSession('Push A', SessionCategory.push, 18, 52, <_SeedExercise>[
      _SeedExercise('Bench Press', 75.0, 8, 7.0, 4),
      _SeedExercise('Overhead Press', 40.0, 10, 7.5, 3),
      _SeedExercise('Tricep Pushdown', 25.0, 12, 8.0, 3),
    ]),
    _SeedSession('Pull A', SessionCategory.pull, 16, 48, <_SeedExercise>[
      _SeedExercise('Barbell Row', 70.0, 8, 7.5, 4),
      _SeedExercise('Lat Pulldown', 55.0, 10, 7.0, 3),
      _SeedExercise('Bicep Curl', 15.0, 12, 8.0, 3),
    ]),
    _SeedSession('Leg Day', SessionCategory.legs, 14, 61, <_SeedExercise>[
      _SeedExercise('Squat', 100.0, 6, 8.0, 4),
      _SeedExercise('Leg Press', 160.0, 10, 7.5, 3),
      _SeedExercise('Romanian Deadlift', 80.0, 10, 7.5, 3),
    ]),
    _SeedSession('Push B', SessionCategory.push, 11, 55, <_SeedExercise>[
      _SeedExercise('Chest Press', 60.0, 10, 7.0, 4),
      _SeedExercise('Incline DB Press', 30.0, 10, 7.5, 3),
      _SeedExercise('Lateral Raise', 12.5, 15, 8.5, 3),
    ]),
    _SeedSession('Pull B', SessionCategory.pull, 9, 47, <_SeedExercise>[
      _SeedExercise('Pull Up', 0.0, 8, 8.0, 4),
      _SeedExercise('Seated Row', 60.0, 10, 7.5, 3),
      _SeedExercise('Bicep Curl', 17.5, 10, 8.0, 3),
    ]),
    _SeedSession('Leg Day', SessionCategory.legs, 7, 58, <_SeedExercise>[
      _SeedExercise('Squat', 105.0, 5, 8.5, 4),
      _SeedExercise('Leg Extension', 50.0, 12, 8.0, 3),
      _SeedExercise('Romanian Deadlift', 85.0, 8, 8.0, 3),
    ]),
    _SeedSession('Push A', SessionCategory.push, 4, 50, <_SeedExercise>[
      _SeedExercise('Bench Press', 82.5, 8, 8.0, 4),
      _SeedExercise('Overhead Press', 45.0, 8, 8.0, 3),
      _SeedExercise('Cable Fly', 20.0, 12, 7.5, 3),
    ]),
    _SeedSession('Pull A', SessionCategory.pull, 2, 53, <_SeedExercise>[
      _SeedExercise('Barbell Row', 77.5, 8, 8.0, 4),
      _SeedExercise('Lat Pulldown', 62.5, 10, 7.5, 3),
      _SeedExercise('Pull Up', 0.0, 10, 8.5, 3),
    ]),
  ];

  // Returns how many sessions were written.
  Future<int> seedDemoData(String userId) async {
    final WriteBatch batch = _db.batch();

    // 1. Exercise library. Ids are captured so sets can reference them.
    final Map<String, String> exerciseIds = <String, String>{};
    for (final (String name, String category, String equipment, String? brand)
        in _exercises) {
      final DocumentReference<Map<String, dynamic>> ref =
          _db.collection('exercises').doc();
      exerciseIds[name] = ref.id;
      batch.set(ref, <String, dynamic>{
        'user_id': userId,
        'name': name,
        'exercise_category': category,
        'equipment_type': equipment,
        'brand': brand,
        'muscle_group': category,
        'is_custom': false,
        'times_logged': 0,
        'best_weight_kg': null,
        'best_reps': null,
        'created_at': FieldValue.serverTimestamp(),
      });
    }

    // 2. Sessions and their sets.
    // Track the heaviest weight seen per exercise so the last time it is
    // beaten can be flagged as a personal best.
    final Map<String, double> heaviest = <String, double>{};

    for (final _SeedSession s in _sessions) {
      final DocumentReference<Map<String, dynamic>> sessionRef =
          _db.collection('sessions').doc();
      final DateTime date =
          DateTime.now().subtract(Duration(days: s.daysAgo));

      double sessionVolume = 0;
      int sessionSetCount = 0;
      bool sessionHasPr = false;

      for (final _SeedExercise ex in s.exercises) {
        final String exerciseId = exerciseIds[ex.name] ?? '';
        final bool isPr = ex.weightKg > (heaviest[ex.name] ?? 0);
        if (isPr) heaviest[ex.name] = ex.weightKg;

        for (int setNo = 1; setNo <= ex.sets; setNo++) {
          // Last set of a PR exercise is the one that earned the record.
          final bool prSet = isPr && setNo == ex.sets;
          if (prSet) sessionHasPr = true;

          sessionVolume += ex.weightKg * ex.reps;
          sessionSetCount++;

          batch.set(_db.collection('sets').doc(), <String, dynamic>{
            'user_id': userId,
            'session_id': sessionRef.id,
            'exercise_id': exerciseId,
            'exercise_name': ex.name,
            'set_number': setNo,
            'weight_kg': ex.weightKg,
            // Reps taper by one on the final set, the way real sets go.
            'reps': setNo == ex.sets ? (ex.reps - 1).clamp(1, 99) : ex.reps,
            'rpe': ex.rpe,
            'is_personal_best': prSet,
            'notes': '',
            'created_at': Timestamp.fromDate(date),
          });
        }
      }

      batch.set(sessionRef, <String, dynamic>{
        'user_id': userId,
        'session_name': s.name,
        'category': s.category.name,
        'session_date': Timestamp.fromDate(date),
        'session_duration': s.durationMinutes * 60,
        'total_volume_kg': sessionVolume,
        'set_count': sessionSetCount,
        'exercise_count': s.exercises.length,
        'has_pr': sessionHasPr,
        'is_active': false,
        'created_at': Timestamp.fromDate(date),
      });
    }

    await batch.commit();
    return _sessions.length;
  }

  // Wipes everything belonging to this user so the demo can be re-run from a
  // clean slate. Firestore has no "delete where" — documents must be read
  // first, then deleted.
  Future<void> clearUserData(String userId) async {
    for (final String collection in <String>['sets', 'sessions', 'exercises']) {
      final QuerySnapshot<Map<String, dynamic>> docs = await _db
          .collection(collection)
          .where('user_id', isEqualTo: userId)
          .get();

      final WriteBatch batch = _db.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in docs.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }
}

// Blueprint types, private to this file.
class _SeedSession {
  const _SeedSession(
    this.name,
    this.category,
    this.daysAgo,
    this.durationMinutes,
    this.exercises,
  );

  final String name;
  final SessionCategory category;
  final int daysAgo;
  final int durationMinutes;
  final List<_SeedExercise> exercises;
}

class _SeedExercise {
  const _SeedExercise(this.name, this.weightKg, this.reps, this.rpe, this.sets);

  final String name;
  final double weightKg;
  final int reps;
  final double rpe;
  final int sets;
}
