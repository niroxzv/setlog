import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

// Local notifications for the rest timer.
//
// The timer itself is a Dart Timer, which only ticks while the app is alive.
// To satisfy the proposal's "even if the phone screen is off or the app is in
// the background", the end-of-rest alert is *scheduled* with the Android alarm
// system the moment the countdown starts, and cancelled if the user stops or
// adjusts it. That way the OS fires the alert regardless of what the app is
// doing.
//
// Every method is a no-op on web: flutter_local_notifications has no web
// implementation, and the spec requires the app to run in a browser without
// errors.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _ready = false;

  // A fixed id means scheduling a new rest alert replaces any previous one,
  // so the user can never stack up several pending alarms.
  static const int restTimerId = 1001;

  // Status bar icon. Deliberately *not* the launcher icon: Android draws a
  // small icon as an alpha-only silhouette, and on API 26+ the launcher icon
  // is an adaptive icon, which cannot be rendered at that size — posting with
  // one drops the notification without an error. See ic_stat_setlog.xml.
  static const String _smallIcon = 'ic_stat_setlog';

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'rest_timer',
    'Rest timer',
    description: 'Alerts you when a rest period between sets is over.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  // Called once from main() before runApp.
  Future<void> init() async {
    if (kIsWeb || _ready) return;

    tz_data.initializeTimeZones();
    // The app is built for a Singapore audience, so the local zone is fixed
    // rather than pulling in a device-timezone plugin for one value.
    tz.setLocalLocation(tz.getLocation('Asia/Singapore'));

    const InitializationSettings settings = InitializationSettings(
      android: AndroidInitializationSettings(_smallIcon),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _plugin.initialize(settings);

    // Android 8+ requires the channel to exist before anything can post to it.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    _ready = true;
  }

  // Android 13+ shows a runtime prompt the first time this is called.
  // Returns false when the user declines, so the UI can explain that the
  // countdown will still run but won't alert in the background.
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    await init();

    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      // Already granted (or running below API 33, where the runtime prompt
      // doesn't exist) — don't ask again.
      final bool alreadyOn =
          await android.areNotificationsEnabled() ?? false;
      if (alreadyOn) return true;

      final bool? result = await android.requestNotificationsPermission();
      // A null result means the platform gave no answer, which is not the
      // same as a refusal. Re-read the real state rather than assuming the
      // worst — treating null as "denied" here silently skipped scheduling
      // altogether.
      return result ?? await android.areNotificationsEnabled() ?? false;
    }

    final IOSFlutterLocalNotificationsPlugin? ios =
        _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  // One description shared by the immediate alert and the scheduled one.
  //
  // Deliberately plain. An earlier version gave the scheduled alert
  // category: alarm and visibility: public, which read well but meant the
  // "test alert" button was exercising a different notification from the one
  // rest actually fires — the test passed while the real alert was dropped.
  // Sharing a single definition makes the test a real test.
  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'rest_timer',
      'Rest timer',
      channelDescription: 'Alerts you when a rest period between sets is over.',
      icon: _smallIcon,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    ),
    iOS: DarwinNotificationDetails(presentSound: true, presentAlert: true),
  );

  // Fires an alert immediately. Used by the "test alert" button so the user
  // can confirm notifications reach them before relying on one mid-workout —
  // and so a failure can be told apart from a scheduling failure.
  Future<void> showTestNow() async {
    if (kIsWeb) return;
    await init();

    await _plugin.show(
      restTimerId + 1,
      'Notifications are working',
      'This is what your rest alert will look like.',
      _details,
    );
  }

  // Whether a notification is actually sitting in the shade right now.
  //
  // show() returning without throwing only means Android accepted the call —
  // the system still drops notifications it can't render. Reading the active
  // list back is the difference between "we asked" and "it worked".
  Future<bool> isShowing(int id) async {
    if (kIsWeb) return false;
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true; // Not checkable on this platform.

    final List<ActiveNotification> active =
        await android.getActiveNotifications();
    return active.any((ActiveNotification n) => n.id == id);
  }

  // How many alerts are booked with the OS. Zero right after starting a rest
  // means the schedule call didn't take, which points at the exact-alarm
  // permission rather than at notifications being off.
  Future<int> pendingCount() async {
    if (kIsWeb) return 0;
    final List<PendingNotificationRequest> pending =
        await _plugin.pendingNotificationRequests();
    return pending.length;
  }

  // Books the end-of-rest alert for `seconds` from now.
  Future<void> scheduleRestFinished({
    required int seconds,
    required String exerciseName,
  }) async {
    if (kIsWeb || seconds <= 0) return;
    await init();

    const NotificationDetails details = _details;

    try {
      await _plugin.zonedSchedule(
        restTimerId,
        'Rest over',
        exerciseName.isEmpty
            ? 'Time for your next set.'
            : 'Time for your next set of $exerciseName.',
        tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds)),
        details,
        // Fires at the exact second even if the device has dozed off.
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        // iOS needs to be told the time is wall-clock, not device-relative.
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } on PlatformException catch (_) {
      // Some OEMs refuse exact alarms even with the permission declared.
      // An inexact alert is better than the feature failing outright.
      await _plugin.zonedSchedule(
        restTimerId,
        'Rest over',
        'Time for your next set.',
        tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds)),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  // Called when the user stops, resets or adjusts the timer.
  Future<void> cancelRestFinished() async {
    if (kIsWeb) return;
    await _plugin.cancel(restTimerId);
  }
}
