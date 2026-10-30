import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/providers/rest_timer_provider.dart';
import 'package:flutter_application_mbapproject/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The proposal's additional feature: a rest timer embedded in the workout
// screen, so sets can be logged and rest tracked without switching screens.
//
// Idle it shows the chosen rest length with - / + controls. Running it shows a
// circular ring draining as the rest period elapses. The alert itself is a
// local notification booked with the OS, so it fires with the screen off.
class RestTimerCard extends ConsumerWidget {
  const RestTimerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final RestTimerState timer = ref.watch(restTimerProvider);
    final RestTimerController controller =
        ref.read(restTimerProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          // Border picks up the energy accent while resting so the card reads
          // as active at a glance.
          color: timer.isRunning
              ? theme.setLog.energy
              : theme.colorScheme.outlineVariant,
          width: timer.isRunning ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.hourglass_bottom,
                size: 18,
                color: timer.isRunning
                    ? theme.setLog.energy
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Rest timer',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              // Lets the user confirm alerts reach them before they rely on
              // one mid-set.
              IconButton(
                icon: const Icon(Icons.notifications_active_outlined),
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: 'Send a test alert',
                onPressed: () async {
                  final String message = await controller.sendTestAlert();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(message)),
                  );
                },
              ),
              if (timer.isRunning)
                TextButton(
                  onPressed: controller.stop,
                  child: const Text('Skip'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _TimerRing(timer: timer, theme: theme),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      timer.isRunning
                          ? (timer.exerciseName.isEmpty
                              ? 'Resting'
                              : 'Resting after ${timer.exerciseName}')
                          : 'Rest between sets',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // - / + adjust the rest length, and per the proposal they
                    // work before *and* during the countdown.
                    Row(
                      children: <Widget>[
                        _StepButton(
                          icon: Icons.remove,
                          tooltip:
                              'Shorten by ${RestTimerState.stepSeconds}s',
                          onPressed: () =>
                              controller.adjust(-RestTimerState.stepSeconds),
                          theme: theme,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _lengthLabel(timer.totalSeconds),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        _StepButton(
                          icon: Icons.add,
                          tooltip: 'Add ${RestTimerState.stepSeconds}s',
                          onPressed: () =>
                              controller.adjust(RestTimerState.stepSeconds),
                          theme: theme,
                        ),
                        const Spacer(),
                        if (!timer.isRunning)
                          FilledButton.icon(
                            onPressed: () => controller.start(),
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('Start'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Honest about the two cases where the background alert won't fire.
          if (kIsWeb) ...<Widget>[
            const SizedBox(height: 10),
            _Note(
              text: 'The countdown runs here, but background alerts are '
                  'Android/iOS only.',
              theme: theme,
            ),
          ] else if (!timer.notificationsAllowed) ...<Widget>[
            const SizedBox(height: 10),
            _Note(
              text: 'Notifications are off, so the alert will only show while '
                  'SetLog is open. Enable them in system settings.',
              theme: theme,
            ),
          ],
        ],
      ),
    );
  }

  String _lengthLabel(int seconds) {
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    if (s == 0) return '${m}m';
    return '${m}m ${s}s';
  }
}

// The depleting ring from the proposal. CircularProgressIndicator with an
// explicit value paints exactly the fraction of rest remaining.
class _TimerRing extends StatelessWidget {
  const _TimerRing({required this.timer, required this.theme});

  final RestTimerState timer;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // Idle shows a full faint ring so the control still reads as a dial.
          SizedBox.expand(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: timer.progress,
                end: timer.isRunning ? timer.progress : 1.0,
              ),
              duration: const Duration(milliseconds: 400),
              builder: (BuildContext context, double value, _) {
                return CircularProgressIndicator(
                  value: value,
                  strokeWidth: 6,
                  strokeCap: StrokeCap.round,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    timer.isRunning
                        ? theme.setLog.energy
                        : theme.colorScheme.outlineVariant,
                  ),
                );
              },
            ),
          ),
          Text(
            timer.isRunning ? timer.label : 'REST',
            style: TextStyle(
              fontSize: timer.isRunning ? 18 : 11,
              fontWeight: FontWeight.w800,
              letterSpacing: timer.isRunning ? 0 : 1.2,
              color: timer.isRunning
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.theme,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        // 44x44 keeps the target within the platform minimum even though the
        // icon itself is 18px.
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.info_outline,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
