import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/models/muscle_activation.dart';
import 'package:flutter_application_mbapproject/models/stats_range.dart';
import 'package:flutter_application_mbapproject/providers/firestore_provider.dart';
import 'package:flutter_application_mbapproject/widgets/body_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_application_mbapproject/theme/app_theme.dart';

// Muscle activation map.
//
// Joins every logged set in the window to the movement it came from, spreads
// that set's volume across the muscles the movement actually trains, then
// colours a body diagram by how hard each muscle was worked relative to the
// hardest-worked one. The breakdown underneath names the exercise responsible
// for each muscle, so a lifter can see *why* a region is lit up.
class MuscleActivationScreen extends ConsumerStatefulWidget {
  const MuscleActivationScreen({super.key, required this.range});

  final StatsRange range;

  @override
  ConsumerState<MuscleActivationScreen> createState() =>
      _MuscleActivationScreenState();
}

class _MuscleActivationScreenState
    extends ConsumerState<MuscleActivationScreen> {
  late StatsRange _range = widget.range;
  BodyView _view = BodyView.front;

  // Legend colours. Warm = heavier load, matching how a heat map is normally
  // read, with untrained regions left neutral grey.
  Map<ActivationTier, Color> _tierColours(ThemeData theme) {
    return <ActivationTier, Color>{
      ActivationTier.primary: theme.colorScheme.primary,
      ActivationTier.secondary: theme.setLog.energy,
      ActivationTier.minimal: theme.setLog.success,
      ActivationTier.none: theme.colorScheme.surfaceContainerHighest,
    };
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<MuscleActivation> activationAsync =
        ref.watch(muscleActivationProvider(_range));
    final Map<ActivationTier, Color> colours = _tierColours(theme);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: activationAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object err, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not build the muscle map.\n$err',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          data: (MuscleActivation activation) => ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              _DarkHeader(
                range: _range,
                activation: activation,
                onRangeChanged: (StatsRange r) => setState(() => _range = r),
                theme: theme,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (activation.isEmpty)
                      _EmptyState(theme: theme)
                    else ...<Widget>[
                      _BodyCard(
                        view: _view,
                        activation: activation,
                        colours: colours,
                        onViewChanged: (BodyView v) =>
                            setState(() => _view = v),
                        theme: theme,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _view == BodyView.front
                            ? 'Front muscles'
                            : 'Back muscles',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Share of volume against your hardest-worked muscle '
                        'in this window.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _MuscleList(
                        loads: activation.forView(_view),
                        colours: colours,
                        theme: theme,
                      ),
                      const SizedBox(height: 20),
                      _NeglectedCard(
                        activation: activation,
                        view: _view,
                        theme: theme,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Dark header
// ──────────────────────────────────────────────────────────────────────

class _DarkHeader extends StatelessWidget {
  const _DarkHeader({
    required this.range,
    required this.activation,
    required this.onRangeChanged,
    required this.theme,
  });

  final StatsRange range;
  final MuscleActivation activation;
  final ValueChanged<StatsRange> onRangeChanged;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 20, 28),
      decoration: BoxDecoration(
        color: theme.setLog.focusPanel,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Back to Progress',
              ),
              const Text(
                'Back',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Spacer(),
              // Range picker mirrors the one on Progress.
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: StatsRange.values.map((StatsRange r) {
                    final bool selected = r == range;
                    return GestureDetector(
                      onTap: () => onRangeChanged(r),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 5),
                        decoration: BoxDecoration(
                          color: selected ? Colors.white : null,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          r.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? theme.setLog.focusPanel
                                : Colors.white70,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  range.windowLabel.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Muscle activation',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  activation.isEmpty
                      ? 'No sets logged in this window'
                      : '${activation.totalSets} sets · '
                          '${activation.totalVolumeKg.toStringAsFixed(0)} kg '
                          'total volume',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Body diagram card + front/back toggle + legend
// ──────────────────────────────────────────────────────────────────────

class _BodyCard extends StatelessWidget {
  const _BodyCard({
    required this.view,
    required this.activation,
    required this.colours,
    required this.onViewChanged,
    required this.theme,
  });

  final BodyView view;
  final MuscleActivation activation;
  final Map<ActivationTier, Color> colours;
  final ValueChanged<BodyView> onViewChanged;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          // Front / back switch.
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: BodyView.values.map((BodyView v) {
                final bool selected = v == view;
                return GestureDetector(
                  onTap: () => onViewChanged(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected ? theme.colorScheme.surface : null,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      v == BodyView.front ? 'Front' : 'Back',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              height: 320,
              child: BodyMap(
                view: view,
                activation: activation,
                tierColours: colours,
                emptyColour: theme.colorScheme.surfaceContainerHighest,
                outlineColour: theme.colorScheme.outlineVariant,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Legend.
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: <Widget>[
              _LegendItem(
                colour: colours[ActivationTier.primary]!,
                label: 'Primary',
                theme: theme,
              ),
              _LegendItem(
                colour: colours[ActivationTier.secondary]!,
                label: 'Secondary',
                theme: theme,
              ),
              _LegendItem(
                colour: colours[ActivationTier.minimal]!,
                label: 'Minimal',
                theme: theme,
              ),
              _LegendItem(
                colour: theme.colorScheme.surfaceContainerHighest,
                label: 'Not trained',
                theme: theme,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.colour,
    required this.label,
    required this.theme,
  });

  final Color colour;
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: colour,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Per-muscle breakdown
// ──────────────────────────────────────────────────────────────────────

class _MuscleList extends StatelessWidget {
  const _MuscleList({
    required this.loads,
    required this.colours,
    required this.theme,
  });

  final List<MuscleLoad> loads;
  final Map<ActivationTier, Color> colours;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (loads.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Text(
          'Nothing on this side of the body was trained in this window.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      children: loads.map((MuscleLoad l) {
        final Color colour = colours[l.tier]!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l.muscle.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                  Text(
                    // "Primary — Bench Press", naming what drove the load.
                    '${l.tier.label} — ${l.topExercise}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: l.share,
                  minHeight: 7,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(colour),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${l.volumeKg.toStringAsFixed(0)} kg credited · '
                '${l.setCount} set${l.setCount == 1 ? '' : 's'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// What you're neglecting — the actionable half of the feature
// ──────────────────────────────────────────────────────────────────────

class _NeglectedCard extends StatelessWidget {
  const _NeglectedCard({
    required this.activation,
    required this.view,
    required this.theme,
  });

  final MuscleActivation activation;
  final BodyView view;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    // Muscles on this view that picked up no volume at all.
    final List<Muscle> untrained = Muscle.values
        .where((Muscle m) => m.view == view)
        .where((Muscle m) => !activation.loads.containsKey(m))
        .toList();

    if (untrained.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.check_circle_outline,
              size: 20,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Full coverage — every muscle on this side got work in this '
                'window.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      );
    }

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
                Icons.warning_amber_rounded,
                size: 18,
                color: theme.setLog.energy,
              ),
              const SizedBox(width: 8),
              Text(
                'Untrained in this window',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: untrained
                .map((Muscle m) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        m.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.accessibility_new,
            size: 44,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Nothing to map yet',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Log some sets, or widen the window above, and your worked '
            'muscles will light up here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
