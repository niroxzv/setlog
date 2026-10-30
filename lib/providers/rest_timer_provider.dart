import 'dart:async';

import 'package:flutter_application_mbapproject/services/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<NotificationService> notificationServiceProvider =
    Provider<NotificationService>((Ref ref) => NotificationService());

// Snapshot of the rest countdown.
class RestTimerState {
  const RestTimerState({
    this.totalSeconds = defaultRestSeconds,
    this.remainingSeconds = 0,
    this.isRunning = false,
    this.exerciseName = '',
    this.notificationsAllowed = true,
  });

  // The proposal's default rest period: 3 minutes.
  static const int defaultRestSeconds = 180;
  static const int minSeconds = 30;
  static const int maxSeconds = 600;
  static const int stepSeconds = 15;

  final int totalSeconds;
  final int remainingSeconds;
  final bool isRunning;

  // Named in the alert so a background notification says which lift is next.
  final String exerciseName;

  // False once the user declines the Android 13+ permission prompt — the
  // countdown still runs on screen, it just can't alert in the background.
  final bool notificationsAllowed;

  bool get isIdle => !isRunning && remainingSeconds == 0;

  // 1.0 at the start, draining to 0. Drives the progress ring.
  double get progress =>
      totalSeconds <= 0 ? 0 : (remainingSeconds / totalSeconds).clamp(0.0, 1.0);

  String get label {
    final int m = remainingSeconds ~/ 60;
    final int s = remainingSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  RestTimerState copyWith({
    int? totalSeconds,
    int? remainingSeconds,
    bool? isRunning,
    String? exerciseName,
    bool? notificationsAllowed,
  }) {
    return RestTimerState(
      totalSeconds: totalSeconds ?? this.totalSeconds,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      isRunning: isRunning ?? this.isRunning,
      exerciseName: exerciseName ?? this.exerciseName,
      notificationsAllowed: notificationsAllowed ?? this.notificationsAllowed,
    );
  }
}

final NotifierProvider<RestTimerController, RestTimerState> restTimerProvider =
    NotifierProvider<RestTimerController, RestTimerState>(
        RestTimerController.new);

// Owns the countdown.
//
// Two things run in parallel and must be kept in step:
//   • a Dart Timer that ticks the on-screen ring once a second
//   • a scheduled OS notification booked for the moment rest ends
//
// The Dart timer dies when Android suspends the app, which is exactly why the
// notification is scheduled up front instead of being fired by the tick
// callback. Any action that changes the end time cancels and re-books it.
class RestTimerController extends Notifier<RestTimerState> {
  Timer? _ticker;

  // Absolute end time, so a resumed app recomputes the true remaining time
  // rather than trusting however many ticks it managed to run.
  DateTime? _endsAt;

  @override
  RestTimerState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const RestTimerState();
  }

  NotificationService get _notifications =>
      ref.read(notificationServiceProvider);

  // Called after a set is logged, and by the play button.
  Future<void> start({String exerciseName = '', int? seconds}) async {
    final int duration = seconds ?? state.totalSeconds;

    _ticker?.cancel();
    _endsAt = DateTime.now().add(Duration(seconds: duration));

    state = state.copyWith(
      totalSeconds: duration,
      remainingSeconds: duration,
      isRunning: true,
      exerciseName: exerciseName,
    );

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());

    final bool allowed = await _notifications.requestPermission();
    state = state.copyWith(notificationsAllowed: allowed);

    await _notifications.cancelRestFinished();
    if (allowed) {
      await _notifications.scheduleRestFinished(
        seconds: duration,
        exerciseName: exerciseName,
      );
    }
  }

  // Sends an alert right now so the user can confirm notifications actually
  // reach them. Returns a message the UI shows in a SnackBar.
  Future<String> sendTestAlert() async {
    try {
      final bool allowed = await _notifications.requestPermission();
      state = state.copyWith(notificationsAllowed: allowed);

      if (!allowed) {
        return 'Notifications are blocked. Enable them for SetLog in your '
            'phone\'s settings, then try again.';
      }

      await _notifications.showTestNow();

      // Read back from the system rather than assumed, so a silently dropped
      // notification doesn't look like a success.
      final bool posted =
          await _notifications.isShowing(NotificationService.restTimerId + 1);
      return posted
          ? 'Test alert sent — check your notification shade.'
          : 'Android accepted the alert but posted nothing. Check SetLog\'s '
              'notification settings.';
    } catch (e) {
      return 'Alert failed: $e';
    }
  }

  Future<void> stop() async {
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
    state = state.copyWith(remainingSeconds: 0, isRunning: false);
    await _notifications.cancelRestFinished();
  }

  // The proposal's + / - buttons. Works before *and* during the countdown:
  // while running, the end time moves and the pending alert is re-booked.
  Future<void> adjust(int deltaSeconds) async {
    final int nextTotal = (state.totalSeconds + deltaSeconds)
        .clamp(RestTimerState.minSeconds, RestTimerState.maxSeconds);

    if (!state.isRunning) {
      state = state.copyWith(totalSeconds: nextTotal);
      return;
    }

    final int nextRemaining = (state.remainingSeconds + deltaSeconds)
        .clamp(0, RestTimerState.maxSeconds);

    if (nextRemaining == 0) {
      await stop();
      return;
    }

    _endsAt = DateTime.now().add(Duration(seconds: nextRemaining));
    state = state.copyWith(
      totalSeconds: nextTotal,
      remainingSeconds: nextRemaining,
    );

    await _notifications.cancelRestFinished();
    if (state.notificationsAllowed) {
      await _notifications.scheduleRestFinished(
        seconds: nextRemaining,
        exerciseName: state.exerciseName,
      );
    }
  }

  void _tick() {
    final DateTime? endsAt = _endsAt;
    if (endsAt == null) return;

    // Derived from the end time rather than decremented, so pausing the app
    // for 30 seconds doesn't leave the ring 30 seconds behind.
    final int remaining = endsAt.difference(DateTime.now()).inSeconds;

    if (remaining <= 0) {
      _ticker?.cancel();
      _ticker = null;
      _endsAt = null;
      // The OS notification has already fired; just settle the UI.
      state = state.copyWith(remainingSeconds: 0, isRunning: false);
      return;
    }

    state = state.copyWith(remainingSeconds: remaining);
  }
}
