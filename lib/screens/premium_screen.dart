import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/models/nets_state.dart';
import 'package:flutter_application_mbapproject/providers/nets_provider.dart';
import 'package:flutter_application_mbapproject/providers/premium_provider.dart';
import 'package:flutter_application_mbapproject/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The proposal's NETS QR payment scenario: unlock SetLog Premium by scanning
// a NETS QR.
//
// The QR is issued by the NETS sandbox rather than drawn locally, so the
// transaction is real as far as the gateway is concerned: NETS returns the
// code, streams a "QR code scanned" event when the payer acts on it, and the
// app then asks NETS for the outcome. Premium is granted only when NETS
// answers with response code 00 — never because the user said they paid.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  @override
  void initState() {
    super.initState();
    // Providers can't be written to during initState, so the request waits
    // for the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bool alreadyPremium = ref.read(premiumProvider).value ?? false;
      if (!alreadyPremium) _request();
    });
  }

  @override
  void dispose() {
    // The countdown and the SSE stream live in the provider, which outlives
    // this screen — drop them when the user leaves.
    ref.read(netsProvider.notifier).reset();
    super.dispose();
  }

  void _request() => ref
      .read(netsProvider.notifier)
      .generateQr(ref.read(selectedTierProvider));

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isPremium = ref.watch(premiumProvider).value ?? false;
    final NetsState nets = ref.watch(netsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('SetLog Premium')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: <Widget>[
          if (isPremium)
            _ActiveCard(theme: theme, onCancel: _confirmCancel)
          else ...<Widget>[
            _TierSelector(
              theme: theme,
              // A new tier means a new amount, so the old QR is void.
              onChanged: (PremiumTier _) => _request(),
            ),
            const SizedBox(height: 4),
            _PaymentPanel(
              nets: nets,
              theme: theme,
              onRetry: _request,
              onDone: () => Navigator.of(context).pop(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmCancel() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Cancel Premium?'),
        content: const Text(
          'You\'ll lose AI follow-up coaching. You can re-subscribe at any '
          'time.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Premium'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(premiumProvider.notifier).cancel();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Premium cancelled.')),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Payment states
// ──────────────────────────────────────────────────────────────────────

class _PaymentPanel extends StatelessWidget {
  const _PaymentPanel({
    required this.nets,
    required this.theme,
    required this.onRetry,
    required this.onDone,
  });

  final NetsState nets;
  final ThemeData theme;
  final VoidCallback onRetry;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    switch (nets.status) {
      case NetsStatus.idle:
      case NetsStatus.loading:
        return _Busy(theme: theme, label: 'Requesting a QR from NETS…');

      case NetsStatus.verifying:
        return _Busy(theme: theme, label: 'Confirming payment with NETS…');

      case NetsStatus.paid:
        return _Outcome(
          theme: theme,
          icon: Icons.check_circle,
          tint: theme.setLog.success,
          title: 'Payment successful',
          detail: nets.message ?? 'SetLog Premium is now active.',
          actionLabel: 'Done',
          onAction: onDone,
        );

      case NetsStatus.failed:
        return _Outcome(
          theme: theme,
          icon: Icons.cancel,
          tint: theme.colorScheme.error,
          title: 'Payment not completed',
          detail: nets.message ?? 'The transaction did not go through.',
          actionLabel: 'Try again',
          onAction: onRetry,
        );

      case NetsStatus.awaitingPayment:
        return _QrCard(nets: nets, theme: theme, onRetry: onRetry);
    }
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.theme, required this.label});
  final ThemeData theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.center,
      child: Column(
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.theme,
    required this.icon,
    required this.tint,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onAction,
  });

  final ThemeData theme;
  final IconData icon;
  final Color tint;
  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tint.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: <Widget>[
              Icon(icon, size: 46, color: tint),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}

class _QrCard extends ConsumerWidget {
  const _QrCard({
    required this.nets,
    required this.theme,
    required this.onRetry,
  });

  final NetsState nets;
  final ThemeData theme;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool expired = nets.hasExpired;
    final PremiumTier tier = ref.watch(selectedTierProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          Text(
            'Scan to pay ${tier.priceLabel} · ${tier.label}',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Open the NETS payment app and scan this code.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // The QR arrives from NETS as a base64 PNG, so it is shown as an
          // image rather than re-encoded from a payload string.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: nets.qrImage == null
                ? const SizedBox(height: 220, width: 220)
                : Opacity(
                    // Dimmed once expired, so a stale code is obviously stale.
                    opacity: expired ? 0.25 : 1,
                    child: Image.memory(
                      nets.qrImage!,
                      height: 220,
                      width: 220,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
          ),
          const SizedBox(height: 14),

          if (expired) ...<Widget>[
            Text(
              'This code has expired.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Get a new code'),
            ),
          ] else ...<Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Expires in ${nets.countdown}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
            if (nets.message != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                nets.message!,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.setLog.success),
              ),
            ],
          ],

          const SizedBox(height: 14),
          Text(
            'NETS sandbox transaction ${nets.txnRef ?? ''}. The app waits for '
            'NETS to report the payment — it does not take your word for it.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────

// Both unlocks, side by side. Picking one re-opens the NETS transaction,
// because the amount is fixed into the QR when it is issued — a different
// price is a different transaction, not a relabelled one.
class _TierSelector extends ConsumerWidget {
  const _TierSelector({required this.theme, required this.onChanged});

  final ThemeData theme;
  final ValueChanged<PremiumTier> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PremiumTier selected = ref.watch(selectedTierProvider);

    return Column(
      children: PremiumTier.values.map((PremiumTier tier) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _TierCard(
            tier: tier,
            selected: tier == selected,
            theme: theme,
            onTap: () {
              if (tier == selected) return;
              ref.read(selectedTierProvider.notifier).state = tier;
              onChanged(tier);
            },
          ),
        );
      }).toList(),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final PremiumTier tier;
  final bool selected;
  final ThemeData theme;
  final VoidCallback onTap;

  static const List<String> _base = <String>[
    'Ask the AI Coach follow-up questions',
    'Detailed post-workout coaching reports',
    'Unlimited training history',
  ];

  @override
  Widget build(BuildContext context) {
    final List<String> perks = <String>[
      ..._base,
      if (tier == PremiumTier.plus) 'Longer, more detailed coach analysis',
    ];

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: <Color>[Color(0xFF00509D), Color(0xFF1E88E5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : theme.colorScheme.surfaceContainerLow,
            border: selected
                ? null
                : Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? Colors.white
                        : theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      tier.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? Colors.white : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tier.priceLabel,
                    style: TextStyle(
                      color: selected ? Colors.white : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                tier.tagline,
                style: TextStyle(
                  color: selected
                      ? Colors.white70
                      : theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              if (selected) ...<Widget>[
                const SizedBox(height: 14),
                ...perks.map((String p) => _Perk(text: p)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_circle, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.theme, required this.onCancel});

  final ThemeData theme;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.setLog.successContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: <Widget>[
              Icon(
                Icons.workspace_premium,
                size: 40,
                color: theme.setLog.onSuccessContainer,
              ),
              const SizedBox(height: 10),
              Text(
                'Premium is active',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.setLog.onSuccessContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'AI Coach follow-up questions are unlocked.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.setLog.onSuccessContainer,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: onCancel,
          child: const Text('Cancel subscription'),
        ),
      ],
    );
  }
}
