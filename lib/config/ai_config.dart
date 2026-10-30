// Configuration for the Applied AI feature (the proposal's Post-Workout
// AI Coach).
//
// The key is read from a compile-time environment variable first, so it can be
// supplied without ever being written into the source:
//
//   flutter run --dart-define=GEMINI_API_KEY=your_key_here
//
// If no --dart-define is given, the AI coach uses its on-device rule engine.
//
// Get a free key at https://aistudio.google.com/app/apikey
class AiConfig {
  const AiConfig._();

  static const String _envKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  // Google AI Studio free tier — no billing account and no card required,
  // which the project brief requires.
  static const String _fallbackKey = ''; // no key in source: pass --dart-define=GEMINI_API_KEY=...

  static String get apiKey => _envKey.isNotEmpty ? _envKey : _fallbackKey;

  // When no key is configured the AI service falls back to its own on-device
  // rule engine, so the feature still works during a demo with no internet.
  static bool get hasApiKey => apiKey.isNotEmpty;

  // Tried in order; the service moves to the next one if a model is
  // unavailable or rate-limited.
  //
  // Both are "lite" models on purpose. The full flash models are reasoning
  // models: they spend output tokens on hidden thinking before answering, and
  // that thinking expands to fill whatever token budget it is given. Asking
  // gemini-flash-latest for this exact prompt burned 1148 tokens on thoughts
  // and returned a reply cut off mid-sentence. The lite models do no thinking,
  // so the whole budget goes to the answer — which for a four-sentence
  // coaching note is all we want anyway, and it is faster.
  static const List<String> models = <String>[
    'gemini-flash-lite-latest',
    'gemini-3.5-flash-lite',
  ];

  static String get model => models.first;
}
