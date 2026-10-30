import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/models/workout_session.dart';

// ──────────────────────────────────────────────────────────────────────
// Semantic colour tokens
// ──────────────────────────────────────────────────────────────────────

// Material's ColorScheme covers primary / surface / error, but SetLog also
// needs colours that mean something specific to training: a personal best, a
// streak, and the near-black "focus" panels used for the timer and AI coach.
//
// Holding them in a ThemeExtension means a widget asks for
// `Theme.of(context).extension<SetLogColors>()!.success` instead of writing
// `Colors.green.shade500` inline. That is what makes the app themable: the
// light and dark themes below supply different values for the same token, and
// every screen follows automatically.
@immutable
class SetLogColors extends ThemeExtension<SetLogColors> {
  const SetLogColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.energy,
    required this.onEnergy,
    required this.focusPanel,
    required this.onFocusPanel,
    required this.categoryPush,
    required this.categoryPull,
    required this.categoryLegs,
    required this.categoryOther,
  });

  // Personal bests, "full coverage", positive deltas.
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  // Streaks, warnings, secondary activation — the fitness "energy" accent.
  final Color energy;
  final Color onEnergy;

  // The dark panels (timer card, streak card, AI coach). Previously hardcoded
  // as 0xFF111418 in five different files.
  final Color focusPanel;
  final Color onFocusPanel;

  // One colour per training split, so a category looks the same everywhere.
  final Color categoryPush;
  final Color categoryPull;
  final Color categoryLegs;
  final Color categoryOther;

  Color category(SessionCategory c) {
    switch (c) {
      case SessionCategory.push:
        return categoryPush;
      case SessionCategory.pull:
        return categoryPull;
      case SessionCategory.legs:
        return categoryLegs;
      case SessionCategory.other:
        return categoryOther;
    }
  }

  @override
  SetLogColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? energy,
    Color? onEnergy,
    Color? focusPanel,
    Color? onFocusPanel,
    Color? categoryPush,
    Color? categoryPull,
    Color? categoryLegs,
    Color? categoryOther,
  }) {
    return SetLogColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      energy: energy ?? this.energy,
      onEnergy: onEnergy ?? this.onEnergy,
      focusPanel: focusPanel ?? this.focusPanel,
      onFocusPanel: onFocusPanel ?? this.onFocusPanel,
      categoryPush: categoryPush ?? this.categoryPush,
      categoryPull: categoryPull ?? this.categoryPull,
      categoryLegs: categoryLegs ?? this.categoryLegs,
      categoryOther: categoryOther ?? this.categoryOther,
    );
  }

  // Lets Flutter cross-fade the tokens when the theme switches.
  @override
  SetLogColors lerp(ThemeExtension<SetLogColors>? other, double t) {
    if (other is! SetLogColors) return this;
    return SetLogColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      energy: Color.lerp(energy, other.energy, t)!,
      onEnergy: Color.lerp(onEnergy, other.onEnergy, t)!,
      focusPanel: Color.lerp(focusPanel, other.focusPanel, t)!,
      onFocusPanel: Color.lerp(onFocusPanel, other.onFocusPanel, t)!,
      categoryPush: Color.lerp(categoryPush, other.categoryPush, t)!,
      categoryPull: Color.lerp(categoryPull, other.categoryPull, t)!,
      categoryLegs: Color.lerp(categoryLegs, other.categoryLegs, t)!,
      categoryOther: Color.lerp(categoryOther, other.categoryOther, t)!,
    );
  }
}

// Shorthands so widgets read `context.setLog.success` or, where a ThemeData
// is already in hand, `theme.setLog.success`.
extension SetLogTheme on BuildContext {
  SetLogColors get setLog => Theme.of(this).extension<SetLogColors>()!;
}

extension SetLogThemeData on ThemeData {
  SetLogColors get setLog => extension<SetLogColors>()!;
}

// ──────────────────────────────────────────────────────────────────────
// Themes
// ──────────────────────────────────────────────────────────────────────

// Material 3 themes built from one blue seed. ColorScheme.fromSeed derives
// the rest of the palette through Material's tonal-palette algorithm, so
// contrast stays accessible in both brightnesses without hand-picking shades.
class AppTheme {
  AppTheme._();

  // SetLog's brand blue — the same value the app icon and splash use.
  static const Color seed = Color(0xFF00509D);

  // Fitness accent, carried through streaks, warnings and the icon's tallest
  // bar. Chosen against the blue for a warm/cool pairing that reads as energy.
  static const Color energySeed = Color(0xFFF97316);
  static const Color successSeed = Color(0xFF16A34A);

  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 16,
  );

  static const double radius = 16;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static SetLogColors _tokens(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    return SetLogColors(
      // Dark mode needs lighter, less saturated variants of the same hues —
      // the light-mode values fail contrast against a dark surface.
      success: isDark ? const Color(0xFF4ADE80) : successSeed,
      onSuccess: isDark ? const Color(0xFF06280F) : Colors.white,
      successContainer:
          isDark ? const Color(0xFF14361F) : const Color(0xFFDCFCE7),
      onSuccessContainer:
          isDark ? const Color(0xFFBBF7D0) : const Color(0xFF14532D),
      energy: isDark ? const Color(0xFFFB923C) : energySeed,
      onEnergy: isDark ? const Color(0xFF2A1206) : Colors.white,
      // In dark mode the focus panels sit slightly *above* the background so
      // they still read as raised, rather than disappearing into it.
      focusPanel:
          isDark ? const Color(0xFF1B2430) : const Color(0xFF111418),
      onFocusPanel: Colors.white,
      categoryPush: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
      categoryPull: isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
      categoryLegs: isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C),
      categoryOther: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
    );
  }

  static ThemeData _build(Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: scheme.surface,
      extensions: <ThemeExtension<dynamic>>[_tokens(brightness)],

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),

      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size.fromHeight(50),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 4,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
