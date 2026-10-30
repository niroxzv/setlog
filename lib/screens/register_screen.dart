import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/providers/firebase_provider.dart';
import 'package:flutter_application_mbapproject/widgets/auth_widgets.dart';
import 'package:flutter_application_mbapproject/screens/auth_gate.dart';
import 'package:flutter_application_mbapproject/screens/login_screen.dart';
import 'package:flutter_application_mbapproject/services/firebase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// New-account form. Display name + email + password + confirm.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    await ref.read(authControllerProvider.notifier).register(
          email: _emailController.text,
          password: _passwordController.text,
          displayName: _nameController.text,
        );

    final AsyncValue<void> result = ref.read(authControllerProvider);
    if (!mounted) return;

    if (result.hasError) {
      _showSnackBar(result.error is AuthException
          ? (result.error! as AuthException).message
          : 'Sign up failed.');
      return;
    }

    await _showVerificationDialog();
    if (!mounted) return;
    // We reached RegisterScreen via pushReplacement from LoginScreen, which
    // removed AuthGate from the stack. A plain pop() would leave an empty
    // Navigator (white screen). Instead re-mount AuthGate as the only route —
    // it sees the now signed-in user and shows MainScreen.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AuthGate()),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _showVerificationDialog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Check your inbox'),
        content: const Text(
          'We sent a verification email to your address. You can keep using '
          'SetLog right away — verifying just helps secure your account.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String msg) {
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
            activeIndex: 1,
            onTapLogIn: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Create account.',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Start logging your sets in under a minute.',
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
            _buildNameField(),
            const SizedBox(height: 12),
            _buildEmailField(),
            const SizedBox(height: 12),
            _buildPasswordField(),
            const SizedBox(height: 12),
            _buildConfirmField(),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: isLoading ? null : _submit,
              child: isLoading
                  ? const ButtonSpinner()
                  : const Text('Create account'),
            ),
            const SizedBox(height: 12),
            Text(
              'By creating an account you agree to be a better lifter.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      keyboardType: TextInputType.name,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'Display name',
        prefixIcon: Icon(Icons.person_outline),
      ),
      validator: (String? value) {
        final String v = (value ?? '').trim();
        if (v.isEmpty) return 'Display name is required';
        if (v.length < 2) return 'Display name is too short';
        return null;
      },
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
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: 'Password',
        prefixIcon: const Icon(Icons.lock_outlined),
        helperText: 'At least 6 characters',
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

  Widget _buildConfirmField() {
    return TextFormField(
      controller: _confirmController,
      obscureText: _obscurePassword,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _submit(),
      decoration: const InputDecoration(
        labelText: 'Confirm password',
        prefixIcon: Icon(Icons.lock_outlined),
      ),
      validator: (String? value) {
        if (value == null || value.isEmpty) {
          return 'Please confirm your password';
        }
        if (value != _passwordController.text) {
          return 'Passwords don\'t match';
        }
        return null;
      },
    );
  }
}
