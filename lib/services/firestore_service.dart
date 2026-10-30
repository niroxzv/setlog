import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_mbapproject/models/exercise.dart';
import 'package:flutter_application_mbapproject/models/logged_set.dart';
import 'package:flutter_application_mbapproject/models/workout_session.dart';

// Result of the aggregation query used by the Stats screen.
class WorkoutStats {
  const WorkoutStats({
    required this.sessionCount,
    required this.totalVolumeKg,
    required this.averageDurationSeconds,
  });

  final int sessionCount;
  final double totalVolumeKg;
  final double averageDurationSeconds;
}

// Wraps Cloud Firestore so widgets never talk to the database directly,
// exactly like FirebaseService does for Auth. Riverpod exposes one instance
// via firestoreServiceProvider.
//
// Every method below is labelled with the rubric category it satisfies:
//   [CRUD]     Select all / Select one / Insert / Update / Delete
//   [QUERY-n]  the five advanced-query categories
class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // Collection names mirror the Part 1 data dictionary tables.
  CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection('sessions');
  CollectionReference<Map<String, dynamic>> get _sets => _db.collection('sets');
  CollectionReference<Map<String, dynamic>> get _exercises =>
      _db.collection('exercises');

  // ────────────────────────────────────────────────────────────────
  // SESSIONS
  // ────────────────────────────────────────────────────────────────

  // [CRUD: Select all] + [QUERY-4: sort order]
  // Every past session for this user, newest first.
  Stream<List<WorkoutSession>> watchSessions(String userId) {
    return _sessions
        .where('user_id', isEqualTo: userId)
        .orderBy('session_date', descending: true)
        .snapshots()
        .map(_toSessionList);
  }

  // [CRUD: Select one]
  // Full detail for a single session, used when a History row is tapped.
  Future<WorkoutSession?> getSession(String sessionId) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await _sessions.doc(sessionId).get();
      if (!doc.exists) return null;
      return WorkoutSession.fromDoc(doc);
    } on FirebaseException catch (e) {
      throw DataException(_mapError(e));
    }
  }

  // [QUERY-1: filter on a non-identifier field]
  // Powers the History filter chips (Push / Pull / Legs).
  Stream<List<WorkoutSession>> watchSessionsByCategory(
    String userId,
    SessionCategory category,
  ) {
    return _sessions
        .where('user_id', isEqualTo: userId)
        .where('category', isEqualTo: category.name)
        .orderBy('session_date', descending: true)
        .snapshots()
        .map(_toSessionList);
  }

  // [QUERY-2: multiple filter criteria on the SAME field]
  // whereIn matches several values of `category` in one query — e.g. show
  // upper-body days by asking for push OR pull together.
  Stream<List<WorkoutSession>> watchSessionsInCategories(
    String userId,
    List<SessionCategory> categories,
  ) {
    return _sessions
        .where('user_id', isEqualTo: userId)
        .where('category',
            whereIn: categories.map((SessionCategory c) => c.name).toList())
        .orderBy('session_date', descending: true)
        .snapshots()
        .map(_toSessionList);
  }

  // [QUERY-5: aggregation]
  // count() / sum() / average() run on Firestore's servers — only the totals
  // come back over the network, not the documents.
  Future<WorkoutStats> aggregateStats(String userId) async {
    try {
      final AggregateQuerySnapshot snap = await _sessions
          .where('user_id', isEqualTo: userId)
          .aggregate(
            count(),
            sum('total_volume_kg'),
            average('session_duration'),
          )
          .get();

      return WorkoutStats(
        sessionCount: snap.count ?? 0,
        totalVolumeKg: snap.getSum('total_volume_kg') ?? 0,
        averageDurationSeconds: snap.getAverage('session_duration') ?? 0,
      );
    } on FirebaseException catch (e) {
      throw DataException(_mapError(e));
    }
  }

  // The workout currently in progress, if any. Drives "Today's session".
  //
  // createSession guarantees at most one active session, but this sorts by
  // date anyway and takes the newest: with a plain limit(1) Firestore returns
  // an arbitrary match, so any session left active by an older build of the
  // app could shadow the one the user just started. Sorting in Dart rather
  // than the query keeps this off the composite-index list — the result set
  // is one document.
  Stream<WorkoutSession?> watchActiveSession(String userId) {
    return _sessions
        .where('user_id', isEqualTo: userId)
        .where('is_active', isEqualTo: true)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> s) {
      if (s.docs.isEmpty) return null;
      final List<WorkoutSession> active = s.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              WorkoutSession.fromDoc(d))
          .toList()
        ..sort((WorkoutSession a, WorkoutSession b) =>
            b.date.compareTo(a.date));
      return active.first;
    });
  }

  // [CRUD: Insert]
  // Starts a session and returns its new document id.
  //
  // A workout that was abandoned rather than finished stays is_active: true
  // forever, which left the home card and the workout timer pointing at a
  // days-old session. Starting a new workout therefore closes any session
  // still marked active first, so exactly one is ever open. Both writes go in
  // one WriteBatch, so the app can never end up with two active sessions or
  // none at all.
  Future<String> createSession(WorkoutSession session) async {
    try {
      final QuerySnapshot<Map<String, dynamic>> stale = await _sessions
          .where('user_id', isEqualTo: session.userId)
          .where('is_active', isEqualTo: true)
          .get();

      final WriteBatch batch = _db.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in stale.docs) {
        batch.update(doc.reference, <String, dynamic>{'is_active': false});
      }

      // Id is generated up front so the new document can join the batch.
      final DocumentReference<Map<String, dynamic>> ref = _sessions.doc();
      batch.set(ref, session.toMap());
      await batch.commit();

      return ref.id;
    } on FirebaseException catch (e) {
      throw DataException(_mapError(e));
    }
  }

  // [CRUD: Update]
  // Used to finish a session (is_active -> false) and write its final totals.
  Future<void> updateSession(
    String sessionId,
    Map<String, dynamic> changes,
  ) async {
    try {
      await _sessions.doc(sessionId).update(changes);
    } on FirebaseException catch (e) {
      throw DataException(_mapError(e));
    }
  }

  // [CRUD: Delete]
  // Removes the session and every set inside it. A WriteBatch makes this
  // atomic — either all of it is deleted or none of it is.
  Future<void> deleteSession(String sessionId) async {
    try {
      final QuerySnapshot<Map<String, dynamic>> childSets =
          await _sets.where('session_id', isEqualTo: sessionId).get();

      final WriteBatch batch = _db.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in childSets.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_sessions.doc(sessionId));
      await batch.commit();
    } on FirebaseException catch (e) {
      throw DataException(_mapError(e));
    }
  }

  // ────────────────────────────────────────────────────────────────
  // SETS
  // ────────────────────────────────────────────────────────────────

  // [CRUD: Select all] — every set belonging to one session, in order.
  Stream<List<LoggedSet>> watchSetsForSession(String sessionId) {
    return _sets
        .where('session_id', isEqualTo: sessionId)
        .orderBy('set_number')
        .snapshots()
        .map(_toSetList);
  }

  // [QUERY-3 variant] — all sets of one exercise for one user, heaviest
  // first. Filters on user_id and exercise_id, then sorts by weight.
  Stream<List<LoggedSet>> watchSetsForExercise(
    String userId,
    String exerciseId,
  ) {
    return _sets
        .where('user_id', isEqualTo: userId)
        .where('exercise_id', isEqualTo: exerciseId)
        .orderBy('weight_kg', descending: true)
        .snapshots()
        .map(_toSetList);
  }

  // [CRUD: Select all] — every set this user has ever logged, feeding the
  // muscle-activation map.
  //
  // Deliberately has no orderBy: a single equality filter is served by
  // Firestore's automatic single-field index, so this needs no composite
  // index of its own. The date window is applied in Dart afterwards, which is
  // cheap at this data volume.
  Stream<List<LoggedSet>> watchAllSets(String userId) {
    return _sets
        .where('user_id', isEqualTo: userId)
        .snapshots()
        .map(_toSetList);
  }

  // [QUERY-3: multiple filter criteria on DIFFERENT fields] + [QUERY-4: sort]
  // The Stats screen's "Recent personal records" list — sets flagged as a
  // personal best, newest first, capped server-side with limit().
  Stream<List<LoggedSet>> watchRecentPersonalBests(
    String userId, {
    int limit = 5,
  }) {
    return _sets
        .where('user_id', isEqualTo: userId)
        .where('is_personal_best', isEqualTo: true)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map(_toSetList);
  }

  // [CRUD: Insert] — log one set.
  Future<String> addSet(LoggedSet set) async {
    try {
      final DocumentReference<Map<String, dynamic>> ref =
          await _sets.add(set.toMap());
      return ref.id;
    } on FirebaseException catch (e) {
      throw DataException(_mapError(e));
    }
  }

  // [CRUD: Update] — edit an existing set's weight / reps / RPE.
  Future<void> updateSet(String setId, Map<String, dynamic> changes) async {
    try {
      await _sets.doc(setId).update(changes);
    } on FirebaseException catch (e) {
      throw DataException(_mapError(e));
    }
  }

  // [CRUD: Delete] — remove a single set.
  Future<void> deleteSet(String setId) async {
    try {
      await _sets.doc(setId).delete();
    } on FirebaseException catch (e) {
      throw DataException(_mapError(e));
    }
  }

  // ────────────────────────────────────────────────────────────────
  // EXERCISES
  // ────────────────────────────────────────────────────────────────

  // [CRUD: Select all] — the exercise library.
  Stream<List<Exercise>> watchExercises(String userId) {
    return _exercises
        .orderBy('name')
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> s) => _mine(s, userId));
  }

  // [QUERY-1 variant] — library filtered to one muscle group.
  Stream<List<Exercise>> watchExercisesByCategory(
    String category,
    String userId,
  ) {
    return _exercises
        .where('exercise_category', isEqualTo: category)
        .orderBy('name')
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> s) => _mine(s, userId));
  }

  // Keeps only this account's exercises.
  //
  // Done in Dart rather than as a third `where` because adding user_id to
  // these queries would need two more composite indexes — user_id + name, and
  // user_id + exercise_category + name — for a collection of a few dozen rows.
  // The same trade-off is made in watchAllSets.
  //
  // Without this the Library showed every account's exercises while "Clear
  // data" only ever removed the signed-in user's, so anything seeded under a
  // different uid stayed on screen and looked like a duplicate.
  List<Exercise> _mine(QuerySnapshot<Map<String, dynamic>> s, String userId) {
    return s.docs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
            Exercise.fromDoc(d))
        .where((Exercise e) => e.userId == userId)
        .toList();
  }

  // [CRUD: Insert] — the proposal's "users create their own exercises".
  Future<String> addExercise(Exercise exercise) async {
    try {
      final DocumentReference<Map<String, dynamic>> ref =
          await _exercises.add(exercise.toMap());
      return ref.id;
    } on FirebaseException catch (e) {
      throw DataException(_mapError(e));
    }
  }

  // [CRUD: Delete] — remove a custom exercise from the library.
  Future<void> deleteExercise(String exerciseId) async {
    try {
      await _exercises.doc(exerciseId).delete();
    } on FirebaseException catch (e) {
      throw DataException(_mapError(e));
    }
  }

  // ────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────

  List<WorkoutSession> _toSessionList(QuerySnapshot<Map<String, dynamic>> s) {
    return s.docs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
            WorkoutSession.fromDoc(d))
        .toList();
  }

  List<LoggedSet> _toSetList(QuerySnapshot<Map<String, dynamic>> s) {
    return s.docs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
            LoggedSet.fromDoc(d))
        .toList();
  }

  // Turn raw Firestore error codes into something a user can read.
  String _mapError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'You don\'t have permission to do that.';
      case 'unavailable':
        return 'Can\'t reach the database — check your connection.';
      case 'not-found':
        return 'That record no longer exists.';
      case 'failed-precondition':
        // Firestore throws this when a composite index is missing; the
        // console link to create it is in e.message.
        return 'This query needs a Firestore index. ${e.message ?? ''}';
      default:
        return e.message ?? 'Something went wrong saving your data.';
    }
  }
}

// Mirrors AuthException so widget code catches one familiar type and shows
// e.message, without Firestore types leaking into the UI layer.
class DataException implements Exception {
  DataException(this.message);
  final String message;

  @override
  String toString() => message;
}
