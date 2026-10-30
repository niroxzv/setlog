import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_application_mbapproject/services/firebase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Three providers, each with a single responsibility:
//   firebaseServiceProvider — singleton FirebaseService.
//   authStateProvider       — streams the current User?, drives AuthGate.
//   authControllerProvider  — AsyncNotifier for one-shot actions (login etc.).

final Provider<FirebaseService> firebaseServiceProvider =
    Provider<FirebaseService>((Ref ref) => FirebaseService());

final StreamProvider<User?> authStateProvider = StreamProvider<User?>(
  (Ref ref) => ref.watch(firebaseServiceProvider).authStateChanges(),
);

// AsyncNotifier so screens can pattern-match on AsyncValue
// (loading / error / data) instead of juggling a bool isLoading flag.
final AsyncNotifierProvider<AuthController, void> authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);

class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  FirebaseService get _service => ref.read(firebaseServiceProvider);

  Future<void> signIn({required String email, required String password}) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(
      () => _service.signInWithEmail(email: email, password: password),
    );
  }

  Future<void> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(() async {
      await _service.registerWithEmail(
        email: email,
        password: password,
        displayName: displayName,
      );
      // One more reload from the outer layer so AuthGate/WorkoutScreen see
      // the fully-populated user (displayName set) rather than whatever
      // stale snapshot the first userChanges() emission handed them.
      await _service.reloadCurrentUser();
    });
  }

  Future<void> sendPasswordReset({required String email}) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(
      () => _service.sendPasswordReset(email: email),
    );
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(_service.signInWithGoogle);
  }

  Future<void> signInAnonymously() async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(_service.signInAnonymously);
  }

  Future<void> signOut() async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(_service.signOut);
  }

  Future<void> sendEmailVerification() async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(_service.sendEmailVerification);
  }

  // Returns true if the reload found the email is now verified.
  Future<bool> reloadAndCheckVerified() async {
    state = const AsyncLoading<void>();
    try {
      final bool verified = await _service.reloadAndCheckVerified();
      state = const AsyncData<void>(null);
      return verified;
    } catch (e, st) {
      state = AsyncError<void>(e, st);
      return false;
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(
      () => _service.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      ),
    );
  }
}
