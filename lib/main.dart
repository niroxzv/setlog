import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/app.dart';
import 'package:flutter_application_mbapproject/firebase_options.dart';
import 'package:flutter_application_mbapproject/services/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Sets up the timezone database and the rest-timer notification channel.
  // No-ops on web, where local notifications aren't supported.
  await NotificationService().init();

  runApp(const ProviderScope(child: SetLogApp()));
}
