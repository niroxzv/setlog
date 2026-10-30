import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_mbapproject/providers/firebase_provider.dart';
import 'package:flutter_application_mbapproject/widgets/auth_widgets.dart';
import 'package:flutter_application_mbapproject/screens/forgot_password_screen.dart';
import 'package:flutter_application_mbapproject/screens/register_screen.dart';
import 'package:flutter_application_mbapproject/services/firebase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Email/password log in + the two not-taught-in-class methods (Google,
// Anonymous). Visual shell comes from AuthScaffold in auth_widgets.dart.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authControllerProvider.notifier).signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
    if (!mounted) return;
    final AsyncValue<void> result = ref.read(authControllerProvider);
    if (result.hasError) _showError(result.error);
    // On success authStateProvider fires and AuthGate swaps to MainScreen.
  }

  Future<void> _googleSignIn() async {
    await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    final AsyncValue<void> result = ref.read(authControllerProvider);
    if (result.hasError) _showError(result.error);
  }

  Future<void> _guestSignIn() async {
    await ref.read(authControllerProvider.notifier).signInAnonymously();
    if (!mounted) return;
    final AsyncValue<void> result = ref.read(authControllerProvider);
    if (result.hasError) _showError(result.error);
  }

  void _showError(Object? error) {
    final String msg = error is AuthException
        ? error.message
        : (error?.toString() ?? 'Something went wrong.');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isLoading = ref.watch(authControllerProvider).isLoading;
    final ThemeData theme = Theme.of(context);

    return AuthScaffold(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const AuthBrandRow(),
          const SizedBox(height: 16),
          AuthSegmentedControl(
            activeIndex: 0,
            onTapSignUp: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => const RegisterScreen()),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Welcome back.',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Log in to continue your streak.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
      form: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildEmailField(),
            const SizedBox(height: 12),
            _buildPasswordField(),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: isLoading ? null : _goToForgotPassword,
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 4),
            ElevatedButton(
              onPressed: isLoading ? null : _submit,
              child: isLoading ? const ButtonSpinner() : const Text('Log in'),
            ),
            const SizedBox(height: 24),
            const OrDivider(),
            const SizedBox(height: 16),
            GoogleSignInButton(onPressed: isLoading ? null : _googleSignIn),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: isLoading ? null : _guestSignIn,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Continue as guest'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      decoration: const InputDecoration(
        labelText: 'Email address',
        prefixIcon: Icon(Icons.email_outlined),
      ),
      validator: (String? value) {
        final String v = (value ?? '').trim();
        if (v.isEmpty) return 'Email is required';
        final RegExp emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
        if (!emailRegex.hasMatch(v)) return 'Enter a valid email address';
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      // Block accidental whitespace inside passwords on iOS.
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.deny(RegExp(r'\s')),
      ],
      onFieldSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        labelText: 'Password',
        prefixIcon: const Icon(Icons.lock_outlined),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextButton(
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              _obscurePassword ? 'SHOW' : 'HIDE',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
      validator: (String? value) {
        if (value == null || value.isEmpty) return 'Password is required';
        if (value.length < 6) return 'Password must be at least 6 characters';
        return null;
      },
    );
  }

  void _goToForgotPassword() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ForgotPasswordScreen()),
    );
  }
}
