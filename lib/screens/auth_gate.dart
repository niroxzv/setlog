import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/providers/firebase_provider.dart';
import 'package:flutter_application_mbapproject/screens/login_screen.dart';
import 'package:flutter_application_mbapproject/screens/main_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Routes to login or main app based on auth state. Watching authStateProvider
// means the tree rebuilds automatically on sign-in/out — no manual navigation.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<dynamic> authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (Object err, _) => Scaffold(
        body: Center(child: Text('Auth error: $err')),
      ),
      data: (dynamic user) =>
          user == null ? const LoginScreen() : const MainScreen(),
    );
  }
}
