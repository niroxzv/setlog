import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/providers/theme_provider.dart';
import 'package:flutter_application_mbapproject/theme/app_theme.dart';
import 'package:flutter_application_mbapproject/screens/auth_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SetLogApp extends ConsumerWidget {
  const SetLogApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reading the saved preference is a disk hit, so it arrives async. Until
    // it does, follow the device setting rather than flashing the wrong theme.
    final ThemeMode mode =
        ref.watch(themeModeProvider).value ?? ThemeMode.system;

    return MaterialApp(
      title: 'SetLog',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      scrollBehavior: const SetLogScrollBehavior(),
      home: const AuthGate(),
    );
  }
}

// Android's default Material scroll behaviour stretches the whole page when
// you drag past the top or bottom. On a data-heavy list that reads like a
// rendering glitch, so this behaviour turns the stretch off app-wide and
// clamps scrolling at the edges instead.
//
// It also registers mouse + trackpad as drag devices so the same build
// scrolls correctly in a desktop web browser, which the spec requires the
// app to run in.
class SetLogScrollBehavior extends MaterialScrollBehavior {
  const SetLogScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  // Returning the child unchanged removes the stretch / glow overlay.
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  // Clamping physics stops the list travelling past its own bounds, so there
  // is nothing left to stretch.
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}
