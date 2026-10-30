import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

// Wraps FirebaseAuth + GoogleSignIn so widgets never talk to Firebase
// directly. Riverpod exposes a single instance via firebaseServiceProvider.
class FirebaseService {
  FirebaseService({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
      : _auth = auth ?? FirebaseAuth.instance,
        _googleSignInOverride = googleSignIn;

  final FirebaseAuth _auth;

  final GoogleSignIn? _googleSignInOverride;
  GoogleSignIn? _googleSignInInstance;

  // Lazy GoogleSignIn — on Flutter Web the ctor asserts that the OAuth
  // client ID meta tag exists in index.html. If it's missing, eager init
  // fires the assertion during service construction even when the user
  // only wants email/password. Creating on first use avoids that.Runs only
  // when called bascially not when firebase is constructed.

  GoogleSignIn get _googleSignIn {
    return _googleSignInInstance ??= _googleSignInOverride ?? GoogleSignIn();
  }

  User? get currentUser => _auth.currentUser;

  // userChanges() (not authStateChanges()) so the Profile screen rebuilds
  // after user.reload() flips emailVerified to true.
  Stream<User?> authStateChanges() => _auth.userChanges();

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final UserCredential cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      // Pull the latest server state so downstream widgets see fresh
      // emailVerified / displayName instead of any cached value.
      await cred.user?.reload();
      return cred;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapAuthError(e));
    }
  }

  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (displayName != null && displayName.trim().isNotEmpty) {
        await cred.user?.updateDisplayName(displayName.trim());
      }
      // Fire the verification email immediately so it's waiting in their
      // inbox by the time they finish onboarding.
      await cred.user?.sendEmailVerification();
      // Reload so the newly-set displayName is visible in the current User.
      await cred.user?.reload();
      return cred;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapAuthError(e));
    }
  }

  Future<void> sendPasswordReset({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapAuthError(e));
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<void> sendEmailVerification() async {
    try {
      final User? user = _auth.currentUser;
      if (user == null) {
        throw AuthException('You must be signed in to verify your email.');
      }
      if (user.emailVerified) {
        throw AuthException('Your email is already verified.');
      }
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapAuthError(e));
    }
  }

  // emailVerified is cached locally — we have to reload() to see fresh state.
  Future<bool> reloadAndCheckVerified() async {
    final User? user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  // Refreshes _auth.currentUser from the server. Needed after register —
  // createUserWithEmailAndPassword fires the first userChanges() event
  // before updateDisplayName/reload finish, so AuthGate can briefly see a
  // user with no displayName. Reads _auth.currentUser (not a captured User
  // reference) so this always reloads whoever is actually signed in now.
  Future<void> reloadCurrentUser() async {
    await _auth.currentUser?.reload();
  }

  // Firebase requires recent auth before sensitive updates, so re-auth first.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final User? user = _auth.currentUser;
      if (user == null || user.email == null) {
        throw AuthException('You must be signed in with an email account.');
      }
      final AuthCredential credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapAuthError(e));
    }
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // user cancelled

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final UserCredential cred =
          await _auth.signInWithCredential(credential);
      // On web the User object can lag behind the credential exchange;
      // reload forces it to hydrate before AuthGate reads it.
      await cred.user?.reload();
      return cred;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapAuthError(e));
    }
  }

  Future<UserCredential> signInAnonymously() async {
    try {
      final UserCredential cred = await _auth.signInAnonymously();
      // Symmetry with the other sign-in paths — cheap on anonymous accounts.
      await cred.user?.reload();
      return cred;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapAuthError(e));
    }
  }

  // Map raw FirebaseAuthException codes to user-friendly messages.
  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address doesn\'t look right.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found for that email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account with that email already exists.';
      case 'weak-password':
        return 'Password is too weak — use at least 6 characters.';
      case 'network-request-failed':
        return 'Network error — check your connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'requires-recent-login':
        return 'Please sign out and sign in again before changing this.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }
}

// UI layers catch this and show e.message in a SnackBar so Firebase types
// don't leak into widget code.
class AuthException implements Exception {
  AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
