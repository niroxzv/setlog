import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/providers/firebase_provider.dart';
import 'package:flutter_application_mbapproject/providers/firestore_provider.dart';
import 'package:flutter_application_mbapproject/providers/premium_provider.dart';
import 'package:flutter_application_mbapproject/providers/theme_provider.dart';
import 'package:flutter_application_mbapproject/screens/change_password_screen.dart';
import 'package:flutter_application_mbapproject/screens/premium_screen.dart';
import 'package:flutter_application_mbapproject/services/firebase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Profile tab — user info + the two not-taught account-management features
// (email verification + change password) + sign out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<dynamic> authState = ref.watch(authStateProvider);
    final ThemeData theme = Theme.of(context);

    // AuthGate guarantees user is non-null here, but we still guard.
    final User? user = authState.value as User?;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: <Widget>[
          _UserHeader(user: user, theme: theme),
          const SizedBox(height: 16),

          // Shown only for email-signup users whose mailbox isn't verified yet.
          // Google sign-in returns emailVerified=true automatically.
          if (!user.isAnonymous && !user.emailVerified)
            _VerifyEmailCard(ref: ref, theme: theme),

          // Anonymous users see an upgrade CTA.
          if (user.isAnonymous) _GuestUpgradeCard(ref: ref, theme: theme),

          // NETS QR scenario from the proposal — paid SetLog Premium tier
          // that unlocks advanced AI coaching and custom plans. Tapping
          // through opens PremiumScreen, which runs the live NETS sandbox
          // flow in NetsService: request the QR, watch the webhook stream,
          // then confirm with a query before premium is granted.
          _NetsPremiumCard(theme: theme),
          const SizedBox(height: 16),

          Text(
            'Account',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          _SettingsTile(
            icon: Icons.lock_outline,
            title: 'Change password',
            // Anonymous + Google users have no password credential to update.
            subtitle: _canChangePassword(user)
                ? 'Update your password (re-auth required)'
                : 'Not available for ${_authMethodLabel(user)} sign-in',
            enabled: _canChangePassword(user),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const ChangePasswordScreen(),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.logout,
            title: 'Sign out',
            subtitle: 'You\'ll need to sign in again next time',
            onTap: () => _confirmSignOut(context, ref),
          ),

          const SizedBox(height: 20),
          Text(
            'Appearance',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const _ThemePicker(),

          const SizedBox(height: 20),
          Text(
            'Sample data',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          _SettingsTile(
            icon: Icons.cloud_download_outlined,
            title: 'Load sample workouts',
            subtitle: 'Writes an exercise library and 8 past sessions',
            onTap: () => _loadSampleData(context, ref),
          ),
          _SettingsTile(
            icon: Icons.delete_sweep_outlined,
            title: 'Clear my workout data',
            subtitle: 'Removes every session, set and exercise you own',
            onTap: () => _confirmClearData(context, ref),
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              'SetLog · CIT2C18 Project',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Only email/password users can change password.
  bool _canChangePassword(User user) {
    if (user.isAnonymous) return false;
    return user.providerData
        .any((UserInfo info) => info.providerId == 'password');
  }

  String _authMethodLabel(User user) {
    if (user.isAnonymous) return 'guest';
    if (user.providerData
        .any((UserInfo i) => i.providerId == 'google.com')) {
      return 'Google';
    }
    return 'this';
  }

  // Seeds Firestore, showing a blocking spinner while the batch commits.
  Future<void> _loadSampleData(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Load sample workouts?'),
        content: const Text(
          'This replaces your data with an exercise library and 8 past '
          'sessions, so there is something to browse. Anything you have '
          'logged yourself will be removed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Load'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final int count =
        await ref.read(workoutControllerProvider.notifier).seedDemoData();
    if (!context.mounted) return;

    final AsyncValue<void> result = ref.read(workoutControllerProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.hasError
              ? 'Could not load sample data: ${result.error}'
              : 'Added $count sessions. Check the History tab.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmClearData(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Clear all workout data?'),
        content: const Text(
          'Every session, set and exercise on this account will be deleted '
          'from Firestore. This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await ref.read(workoutControllerProvider.notifier).clearMyData();
    if (!context.mounted) return;

    final AsyncValue<void> result = ref.read(workoutControllerProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.hasError
              ? 'Could not clear data: ${result.error}'
              : 'All workout data cleared.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You can sign back in anytime. Any unsaved sets in the current '
          'session will be kept locally.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).signOut();
    // AuthGate will swap us back to LoginScreen automatically.
  }
}

// ──────────────────────────────────────────────────────────────────────
// Theme picker — the user-controlled half of App Personalisation
// ──────────────────────────────────────────────────────────────────────

// Writing the choice through ThemeController persists it to device storage,
// so the app reopens in the theme the user picked rather than resetting.
class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ThemeMode current =
        ref.watch(themeModeProvider).value ?? ThemeMode.system;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.palette_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Theme',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Choose how SetLog looks. "System" follows your phone\'s setting.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          // SegmentedButton gives each option a 48dp-tall touch target and
          // announces its selected state to screen readers for free.
          SegmentedButton<ThemeMode>(
            segments: const <ButtonSegment<ThemeMode>>[
              ButtonSegment<ThemeMode>(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Light'),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_outlined),
                label: Text('System'),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Dark'),
              ),
            ],
            selected: <ThemeMode>{current},
            showSelectedIcon: false,
            onSelectionChanged: (Set<ThemeMode> picked) {
              ref.read(themeModeProvider.notifier).setMode(picked.first);
            },
          ),
        ],
      ),
    );
  }
}

class _UserHeader extends StatelessWidget {
  const _UserHeader({required this.user, required this.theme});
  final User user;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final String name = user.isAnonymous
        ? 'Guest user'
        : (user.displayName?.isNotEmpty == true
            ? user.displayName!
            : (user.email ?? 'Lifter'));

    final String? email = user.isAnonymous ? null : user.email;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 32,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              _initials(name),
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (email != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer
                          .withValues(alpha: 0.8),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                _VerifiedPill(user: user, theme: theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // "Toh Jun Yu" -> "TY".
  String _initials(String name) {
    final List<String> parts =
        name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _VerifiedPill extends StatelessWidget {
  const _VerifiedPill({required this.user, required this.theme});
  final User user;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final String label;
    late final Color bg;

    if (user.isAnonymous) {
      icon = Icons.visibility_outlined;
      label = 'Guest';
      bg = theme.colorScheme.tertiaryContainer;
    } else if (user.emailVerified) {
      icon = Icons.verified;
      label = 'Verified';
      bg = theme.colorScheme.secondaryContainer;
    } else {
      icon = Icons.error_outline;
      label = 'Email not verified';
      bg = theme.colorScheme.errorContainer;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _VerifyEmailCard extends StatelessWidget {
  const _VerifyEmailCard({required this.ref, required this.theme});
  final WidgetRef ref;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.mark_email_unread_outlined,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Text(
                'Verify your email',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'We sent a verification link to your inbox. Click it, then tap '
            '"I verified" to refresh your status.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _resend(context),
                  child: const Text('Resend email'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _refresh(context),
                  child: const Text('I verified'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _resend(BuildContext context) async {
    await ref.read(authControllerProvider.notifier).sendEmailVerification();
    if (!context.mounted) return;
    final AsyncValue<void> result = ref.read(authControllerProvider);
    final String msg = result.hasError
        ? (result.error is AuthException
            ? (result.error! as AuthException).message
            : 'Could not send email.')
        : 'Verification email sent.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _refresh(BuildContext context) async {
    final bool verified =
        await ref.read(authControllerProvider.notifier).reloadAndCheckVerified();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(verified
            ? 'Email verified — thanks!'
            : 'Still not verified. Check your inbox.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _GuestUpgradeCard extends StatelessWidget {
  const _GuestUpgradeCard({required this.ref, required this.theme});
  final WidgetRef ref;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.upgrade,
                  color: theme.colorScheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Text(
                'Save your progress',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'You\'re using SetLog as a guest. Create an account to back up '
            'your sets and access them on another device.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          // Signing out lets the guest register a fresh account for now.
          ElevatedButton(
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            child: const Text('Create an account'),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: ListTile(
        enabled: enabled,
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: enabled ? onTap : null,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// NETS QR Premium upgrade — placeholder for the Part 3 payment flow.
// Tapping the button shows a dialog with a NETS QR code so the user can
// scan to upgrade to SetLog Premium. No real charge happens yet.
// ──────────────────────────────────────────────────────────────────────

// Entry point into the NETS QR upgrade flow. Reflects the current
// subscription state so the tile reads correctly either way.
class _NetsPremiumCard extends ConsumerWidget {
  const _NetsPremiumCard({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isPremium = ref.watch(premiumProvider).value ?? false;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const PremiumScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFF00509D), Color(0xFF1E88E5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.workspace_premium, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'SetLog Premium',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isPremium
                        ? Colors.greenAccent.shade400
                        : Colors.amber.shade400,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isPremium ? 'ACTIVE' : 'PRO',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isPremium
                  ? 'Your unlock is active. AI Coach follow-up questions '
                      'are unlocked.'
                  : 'Unlock AI Coach follow-up questions and detailed coaching '
                      'reports. Pay once with NETS QR — from '
                      '${PremiumTier.standard.priceLabel}.',
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const PremiumScreen(),
                      ),
                    ),
                    icon: Icon(
                      isPremium ? Icons.receipt_long : Icons.qr_code_2,
                    ),
                    label: Text(
                      isPremium ? 'Manage subscription' : 'Pay with NETS QR',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF00509D),
                      textStyle:
                          const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
