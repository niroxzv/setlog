import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_application_mbapproject/models/exercise.dart';
import 'package:flutter_application_mbapproject/models/logged_set.dart';
import 'package:flutter_application_mbapproject/models/muscle_activation.dart';
import 'package:flutter_application_mbapproject/models/stats_range.dart';
import 'package:flutter_application_mbapproject/models/workout_session.dart';
import 'package:flutter_application_mbapproject/providers/firebase_provider.dart';
import 'package:flutter_application_mbapproject/services/firestore_service.dart';
import 'package:flutter_application_mbapproject/services/seed_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Same three-layer shape as firebase_provider.dart:
//   firestoreServiceProvider — singleton FirestoreService
//   read providers           — StreamProvider / FutureProvider for queries
//   workoutControllerProvider — AsyncNotifier for one-shot writes

final Provider<FirestoreService> firestoreServiceProvider =
    Provider<FirestoreService>((Ref ref) => FirestoreService());

// Only used by the "sample data" tools on the Profile screen.
final Provider<SeedService> seedServiceProvider =
    Provider<SeedService>((Ref ref) => SeedService());

// Current signed-in user's id, derived from the auth stream. Every query
// filters on this so one user can never read another user's data.
final Provider<String?> currentUserIdProvider = Provider<String?>((Ref ref) {
  final AsyncValue<User?> auth = ref.watch(authStateProvider);
  return auth.value?.uid;
});

// Which History filter chip is active.
final StateProvider<HistoryFilter> sessionFilterProvider =
    StateProvider<HistoryFilter>((Ref ref) => HistoryFilter.all);

// History list. The selected chip picks which Firestore query runs, so all
// three shapes below are executed by the database rather than by Dart:
//
//   All          watchSessions            [CRUD: Select all] + [QUERY-4 sort]
//   Push/Pull/…  watchSessionsByCategory  [QUERY-1 filter on a non-id field]
//   Upper body   watchSessionsInCategories[QUERY-2 several values, same field]
final StreamProvider<List<WorkoutSession>> sessionsProvider =
    StreamProvider<List<WorkoutSession>>((Ref ref) {
  final String? uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream<List<WorkoutSession>>.value(const <WorkoutSession>[]);
  }

  final FirestoreService service = ref.watch(firestoreServiceProvider);
  final HistoryFilter filter = ref.watch(sessionFilterProvider);

  final List<SessionCategory>? several = filter.multipleCategories;
  if (several != null) {
    return service.watchSessionsInCategories(uid, several);
  }

  final SessionCategory? single = filter.singleCategory;
  return single == null
      ? service.watchSessions(uid)
      : service.watchSessionsByCategory(uid, single);
});

// Every session, ignoring the History chip. The Stats screen and the workout
// calendar need the full picture regardless of what History is filtered to.
final StreamProvider<List<WorkoutSession>> allSessionsProvider =
    StreamProvider<List<WorkoutSession>>((Ref ref) {
  final String? uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream<List<WorkoutSession>>.value(const <WorkoutSession>[]);
  }
  return ref.watch(firestoreServiceProvider).watchSessions(uid);
});

// Most recent personal bests, for the Stats screen.
final StreamProvider<List<LoggedSet>> recentPrsProvider =
    StreamProvider<List<LoggedSet>>((Ref ref) {
  final String? uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream<List<LoggedSet>>.value(const <LoggedSet>[]);
  return ref.watch(firestoreServiceProvider).watchRecentPersonalBests(uid);
});

// The in-progress workout, if there is one. Drives "Today's session".
final StreamProvider<WorkoutSession?> activeSessionProvider =
    StreamProvider<WorkoutSession?>((Ref ref) {
  final String? uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream<WorkoutSession?>.value(null);
  return ref.watch(firestoreServiceProvider).watchActiveSession(uid);
});

// Sets belonging to one session. `.family` lets the screen pass the id in.
final StreamProviderFamily<List<LoggedSet>, String> sessionSetsProvider =
    StreamProvider.family<List<LoggedSet>, String>((Ref ref, String sessionId) {
  return ref.watch(firestoreServiceProvider).watchSetsForSession(sessionId);
});

// One session's full record, for the detail screen (Select one).
final FutureProviderFamily<WorkoutSession?, String> sessionDetailProvider =
    FutureProvider.family<WorkoutSession?, String>(
        (Ref ref, String sessionId) {
  return ref.watch(firestoreServiceProvider).getSession(sessionId);
});

// Server-side count / sum / average for the Stats screen.
final FutureProvider<WorkoutStats> workoutStatsProvider =
    FutureProvider<WorkoutStats>((Ref ref) async {
  final String? uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return const WorkoutStats(
      sessionCount: 0,
      totalVolumeKg: 0,
      averageDurationSeconds: 0,
    );
  }
  return ref.watch(firestoreServiceProvider).aggregateStats(uid);
});

// The exercise library.
final StreamProvider<List<Exercise>> exercisesProvider =
    StreamProvider<List<Exercise>>((Ref ref) {
  final String? uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream<List<Exercise>>.value(const <Exercise>[]);

  return ref.watch(firestoreServiceProvider).watchExercises(uid);
});

// Which muscle-group chip is active on the Library screen. null means "All".
final StateProvider<String?> exerciseCategoryFilterProvider =
    StateProvider<String?>((Ref ref) => null);

// [QUERY-1] The Library list. Like sessionsProvider, picking a chip swaps the
// underlying Firestore query rather than filtering the list in Dart, so the
// database does the work.
final StreamProvider<List<Exercise>> libraryExercisesProvider =
    StreamProvider<List<Exercise>>((Ref ref) {
  final FirestoreService service = ref.watch(firestoreServiceProvider);
  final String? category = ref.watch(exerciseCategoryFilterProvider);
  final String? uid = ref.watch(currentUserIdProvider);

  if (uid == null) return Stream<List<Exercise>>.value(const <Exercise>[]);

  return category == null
      ? service.watchExercises(uid)
      : service.watchExercisesByCategory(category, uid);
});

// [QUERY-3 variant] Every set this user has ever logged for one exercise,
// heaviest first — the personal-best history on the exercise detail sheet.
final StreamProviderFamily<List<LoggedSet>, String> exerciseHistoryProvider =
    StreamProvider.family<List<LoggedSet>, String>(
        (Ref ref, String exerciseId) {
  final String? uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream<List<LoggedSet>>.value(const <LoggedSet>[]);
  return ref
      .watch(firestoreServiceProvider)
      .watchSetsForExercise(uid, exerciseId);
});

// Every set this user has logged. Backs the muscle-activation map.
final StreamProvider<List<LoggedSet>> allSetsProvider =
    StreamProvider<List<LoggedSet>>((Ref ref) {
  final String? uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream<List<LoggedSet>>.value(const <LoggedSet>[]);
  return ref.watch(firestoreServiceProvider).watchAllSets(uid);
});

// Joins sets to their exercises and spreads each set's volume across the
// muscles that movement actually trains. Keyed by range so switching 4w/3m/6m
// recomputes without refetching.
final FutureProviderFamily<MuscleActivation, StatsRange>
    muscleActivationProvider =
    FutureProvider.family<MuscleActivation, StatsRange>(
        (Ref ref, StatsRange range) async {
  final List<LoggedSet> allSets = await ref.watch(allSetsProvider.future);
  final List<Exercise> exercises = await ref.watch(exercisesProvider.future);
  final List<WorkoutSession> sessions =
      await ref.watch(allSessionsProvider.future);

  // Sets don't carry a date of their own that is reliable before the server
  // timestamp resolves, so the window is applied via each set's session.
  final DateTime cutoff = range.cutoff;
  final Set<String> sessionsInWindow = sessions
      .where((WorkoutSession s) => !s.date.isBefore(cutoff))
      .map((WorkoutSession s) => s.id)
      .toSet();

  final List<LoggedSet> windowed = allSets
      .where((LoggedSet s) => sessionsInWindow.contains(s.sessionId))
      .toList();

  return computeMuscleActivation(
    sets: windowed,
    exercisesById: <String, Exercise>{
      for (final Exercise e in exercises) e.id: e,
    },
  );
});

// ────────────────────────────────────────────────────────────────
// Writes
// ────────────────────────────────────────────────────────────────

final AsyncNotifierProvider<WorkoutController, void> workoutControllerProvider =
    AsyncNotifierProvider<WorkoutController, void>(WorkoutController.new);

class WorkoutController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  FirestoreService get _service => ref.read(firestoreServiceProvider);
  String? get _uid => ref.read(currentUserIdProvider);

  // Insert — start a new workout and hand back its id so the caller can
  // navigate straight into it.
  Future<String?> startSession({
    required String name,
    required SessionCategory category,
  }) async {
    final String? uid = _uid;
    if (uid == null) return null;

    state = const AsyncLoading<void>();
    try {
      final String id = await _service.createSession(
        WorkoutSession(
          id: '',
          userId: uid,
          name: name,
          category: category,
          date: DateTime.now(),
          isActive: true,
        ),
      );
      state = const AsyncData<void>(null);
      return id;
    } catch (e, st) {
      state = AsyncError<void>(e, st);
      return null;
    }
  }

  // Update — close the session and store its final totals.
  Future<void> finishSession({
    required String sessionId,
    required int durationSeconds,
    required double totalVolumeKg,
    required int setCount,
    required int exerciseCount,
    required bool hasPr,
  }) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(
      () => _service.updateSession(sessionId, <String, dynamic>{
        'is_active': false,
        'session_duration': durationSeconds,
        'total_volume_kg': totalVolumeKg,
        'set_count': setCount,
        'exercise_count': exerciseCount,
        'has_pr': hasPr,
      }),
    );

    // sessionDetailProvider is a FutureProvider, so it is holding the copy of
    // the document that was read *before* the totals above were written.
    // Without this the summary screen shows the pre-finish values — a blank
    // duration in particular. Dropping the cache forces a fresh read.
    ref.invalidate(sessionDetailProvider(sessionId));
    // The all-time aggregation is a one-shot read too.
    ref.invalidate(workoutStatsProvider);
  }

  // Delete — session plus all of its sets.
  Future<void> deleteSession(String sessionId) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(() => _service.deleteSession(sessionId));
  }

  // Insert — log one set into the current session.
  Future<void> logSet({
    required String sessionId,
    required String exerciseId,
    required String exerciseName,
    required int setNumber,
    required double weightKg,
    required int reps,
    double? rpe,
    String notes = '',
  }) async {
    final String? uid = _uid;
    if (uid == null) return;

    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(
      () => _service.addSet(
        LoggedSet(
          id: '',
          userId: uid,
          sessionId: sessionId,
          exerciseId: exerciseId,
          exerciseName: exerciseName,
          setNumber: setNumber,
          weightKg: weightKg,
          reps: reps,
          rpe: rpe,
          notes: notes,
        ),
      ),
    );
  }

  // Update — edit an already-logged set.
  Future<void> updateSet({
    required String setId,
    required double weightKg,
    required int reps,
    double? rpe,
  }) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(
      () => _service.updateSet(setId, <String, dynamic>{
        'weight_kg': weightKg,
        'reps': reps,
        'rpe': rpe,
      }),
    );
  }

  // Delete — remove one set.
  Future<void> deleteSet(String setId) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(() => _service.deleteSet(setId));
  }

  // Resets Firestore to the starter library and sample sessions, so a fresh
  // account has meaningful data to read. Returns how many sessions were
  // written.
  //
  // The user's existing data is cleared first, which makes this idempotent:
  // it previously only ever added, so a second tap produced a second copy of
  // all 16 exercises and every sample session.
  Future<int> seedDemoData() async {
    final String? uid = _uid;
    if (uid == null) return 0;

    state = const AsyncLoading<void>();
    try {
      await ref.read(seedServiceProvider).clearUserData(uid);
      final int count =
          await ref.read(seedServiceProvider).seedDemoData(uid);
      state = const AsyncData<void>(null);
      return count;
    } catch (e, st) {
      state = AsyncError<void>(e, st);
      return 0;
    }
  }

  // Deletes every session, set and exercise belonging to this user.
  Future<void> clearMyData() async {
    final String? uid = _uid;
    if (uid == null) return;

    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(
      () => ref.read(seedServiceProvider).clearUserData(uid),
    );
  }

  // Insert — the proposal's user-created exercise, with equipment type
  // and brand.
  Future<void> addExercise({
    required String name,
    required String category,
    required String equipmentType,
    String? brand,
    String muscleGroup = '',
  }) async {
    final String? uid = _uid;
    if (uid == null) return;

    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(
      () => _service.addExercise(
        Exercise(
          id: '',
          userId: uid,
          name: name,
          category: category,
          equipmentType: equipmentType,
          brand: brand,
          muscleGroup: muscleGroup,
          isCustom: true,
        ),
      ),
    );
  }
}
