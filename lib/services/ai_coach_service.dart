import 'dart:convert';

import 'package:flutter_application_mbapproject/config/ai_config.dart';
import 'package:flutter_application_mbapproject/models/logged_set.dart';
import 'package:flutter_application_mbapproject/models/workout_session.dart';
import 'package:http/http.dart' as http;

// Raised when a model is retired or out of free-tier quota, so the caller
// knows to try the next model rather than give up on the request.
class _ModelUnavailable implements Exception {
  const _ModelUnavailable(this.model, this.statusCode);

  final String model;
  final int statusCode;

  @override
  String toString() => '$model returned $statusCode.';
}

// One message in the AI Coach conversation.
class CoachMessage {
  const CoachMessage({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}

// The opening analysis: a one-line verdict for the collapsed card plus the
// full write-up shown once the card is expanded.
class CoachAdvice {
  const CoachAdvice({
    required this.headline,
    required this.detail,
    required this.isLive,
  });

  final String headline;
  final String detail;

  // false when the on-device fallback produced this instead of the model,
  // so the UI can label it honestly rather than passing it off as AI output.
  final bool isLive;
}

// The proposal's Applied AI feature — "Post-Workout AI Coach: after a workout
// session is logged, the AI analyses the weight, reps and RPE values and
// returns a personalised recommendation: whether to increase weight, maintain
// current load, or deload."
//
// Talks to Google Gemini over its REST API. If no key is configured, or the
// call fails, [_offlineAdvice] produces a recommendation from the same
// weight/reps/RPE numbers using plain Dart, so the feature never leaves a
// blank card in front of a marker.
class AiCoachService {
  AiCoachService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models';

  // How the model is told to behave. Kept short and specific — a vague system
  // prompt is what makes an LLM answer in generic filler.
  static const String _persona =
      'You are a strength coach reviewing one gym session. Be specific and '
      'reference the actual numbers you are given. Never invent sets that are '
      'not listed. Keep to plain text, no markdown headings, no asterisks. '
      'Use kilograms. Address the lifter as "you".';

  // ────────────────────────────────────────────────────────────────
  // Opening analysis
  // ────────────────────────────────────────────────────────────────

  Future<CoachAdvice> analyseSession({
    required WorkoutSession? session,
    required List<LoggedSet> sets,
    // Set from the purchased tier — Premium Plus buys a longer reply.
    int maxTokens = 400,
  }) async {
    if (sets.isEmpty) {
      return const CoachAdvice(
        headline: 'No sets to analyse yet',
        detail: 'Log a few sets and the coach will review them for you.',
        isLive: false,
      );
    }

    if (!AiConfig.hasApiKey) return _offlineAdvice(sets);

    final String prompt = '''
Here is the workout I just finished.

${_sessionSummary(session, sets)}

Reply in exactly this shape:
Line 1: a verdict of at most 8 words, starting with one of
Increase weight / Maintain load / Deload.
Then a blank line.
Then 3 to 4 short sentences explaining the verdict using the RPE and volume
figures above, and give one concrete target for the next session.''';

    try {
      final String raw = await _generate(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'role': 'user',
            'parts': <Map<String, String>>[
              <String, String>{'text': prompt},
            ],
          },
        ],
        maxTokens: maxTokens,
      );

      // First line is the verdict, the remainder is the expanded detail.
      final List<String> parts = raw.trim().split(RegExp(r'\n\s*\n'));
      final String headline = parts.first.trim().replaceAll('\n', ' ');
      final String detail =
          parts.length > 1 ? parts.sublist(1).join('\n\n').trim() : raw.trim();

      return CoachAdvice(headline: headline, detail: detail, isLive: true);
    } catch (_) {
      // Network down, quota hit, bad key — fall back rather than error out.
      return _offlineAdvice(sets);
    }
  }

  // ────────────────────────────────────────────────────────────────
  // Follow-up questions
  // ────────────────────────────────────────────────────────────────

  // The whole conversation is replayed on each turn so the model keeps the
  // thread — the REST API itself is stateless.
  Future<String> askFollowUp({
    required WorkoutSession? session,
    required List<LoggedSet> sets,
    required List<CoachMessage> history,
    required String question,
    // Set from the purchased tier — Premium Plus buys a longer reply.
    int maxTokens = 400,
  }) async {
    if (!AiConfig.hasApiKey) {
      return 'The AI Coach needs a Gemini API key to answer follow-up '
          'questions. Add one in lib/config/ai_config.dart, or run the app '
          'with --dart-define=GEMINI_API_KEY=your_key.';
    }

    final List<Map<String, dynamic>> contents = <Map<String, dynamic>>[
      <String, dynamic>{
        'role': 'user',
        'parts': <Map<String, String>>[
          <String, String>{
            'text': 'Session data for reference:\n'
                '${_sessionSummary(session, sets)}',
          },
        ],
      },
      for (final CoachMessage m in history)
        <String, dynamic>{
          'role': m.fromUser ? 'user' : 'model',
          'parts': <Map<String, String>>[
            <String, String>{'text': m.text},
          ],
        },
      <String, dynamic>{
        'role': 'user',
        'parts': <Map<String, String>>[
          <String, String>{'text': question},
        ],
      },
    ];

    try {
      return await _generate(contents, maxTokens: maxTokens);
    } catch (e) {
      return 'Could not reach the AI Coach right now. $e';
    }
  }

  // ────────────────────────────────────────────────────────────────
  // Gemini REST call
  // ────────────────────────────────────────────────────────────────

  // Tries each configured model in turn.
  //
  // Which Gemini models are on the free tier changes over time — gemini-2.0-
  // flash was free and later moved to a quota of zero, which surfaces as a 429
  // rather than as anything obviously wrong. Falling through to the next model
  // on 404 (retired) and 429 (out of quota) keeps the coach live instead of
  // silently dropping to the offline rule engine mid-demo.
  Future<String> _generate(
    List<Map<String, dynamic>> contents, {
    int maxTokens = 400,
  }) async {
    Object? lastError;

    for (final String model in AiConfig.models) {
      try {
        return await _generateWith(model, contents, maxTokens: maxTokens);
      } on _ModelUnavailable catch (e) {
        lastError = e;
      }
    }

    throw Exception('No Gemini model available. $lastError');
  }

  Future<String> _generateWith(
    String model,
    List<Map<String, dynamic>> contents, {
    required int maxTokens,
  }) async {
    final Uri url = Uri.parse(
      '$_endpoint/$model:generateContent?key=${AiConfig.apiKey}',
    );

    final http.Response res = await _client
        .post(
          url,
          headers: <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, dynamic>{
            'systemInstruction': <String, dynamic>{
              'parts': <Map<String, String>>[
                <String, String>{'text': _persona},
              ],
            },
            'contents': contents,
            'generationConfig': <String, dynamic>{
              'temperature': 0.7,
              'maxOutputTokens': maxTokens,
            },
          }),
        )
        .timeout(const Duration(seconds: 25));

    // 404 = model retired, 429 = free-tier quota exhausted. Both mean "try the
    // next model"; anything else is a real failure worth reporting.
    if (res.statusCode == 404 || res.statusCode == 429) {
      throw _ModelUnavailable(model, res.statusCode);
    }
    if (res.statusCode != 200) {
      throw Exception('Gemini returned ${res.statusCode}.');
    }

    final Map<String, dynamic> body =
        jsonDecode(res.body) as Map<String, dynamic>;
    final List<dynamic>? candidates = body['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('The model returned no answer.');
    }

    final Map<String, dynamic> content =
        (candidates.first as Map<String, dynamic>)['content']
            as Map<String, dynamic>;
    final List<dynamic> parts = content['parts'] as List<dynamic>;

    final String text = parts
        .map((dynamic p) => (p as Map<String, dynamic>)['text'] as String? ?? '')
        .join()
        .trim();

    if (text.isEmpty) throw Exception('The model returned an empty answer.');
    return text;
  }

  // ────────────────────────────────────────────────────────────────
  // Prompt input + offline fallback
  // ────────────────────────────────────────────────────────────────

  // Flattens the session into the plain-text block the model reasons over.
  String _sessionSummary(WorkoutSession? session, List<LoggedSet> sets) {
    final Map<String, List<LoggedSet>> byExercise = <String, List<LoggedSet>>{};
    for (final LoggedSet s in sets) {
      byExercise.putIfAbsent(s.exerciseName, () => <LoggedSet>[]).add(s);
    }

    final StringBuffer b = StringBuffer()
      ..writeln('Session: ${session?.name ?? 'Workout'}')
      ..writeln('Type: ${session?.category.name ?? 'general'}')
      ..writeln('Total sets: ${sets.length}')
      ..writeln('Total volume: ${_totalVolume(sets).toStringAsFixed(0)} kg');

    final double? avg = _averageRpe(sets);
    if (avg != null) b.writeln('Average RPE: ${avg.toStringAsFixed(1)}');
    if (session != null && session.durationSeconds > 0) {
      b.writeln('Duration: ${(session.durationSeconds / 60).round()} min');
    }

    b.writeln('\nExercises:');
    byExercise.forEach((String name, List<LoggedSet> group) {
      final String detail = group
          .map((LoggedSet s) =>
              '${s.weightKg.toStringAsFixed(1)}kg x ${s.reps}'
              '${s.rpe != null ? ' @RPE${s.rpe!.toStringAsFixed(1)}' : ''}'
              '${s.isPersonalBest ? ' (PB)' : ''}')
          .join(', ');
      b.writeln('- $name: $detail');
    });

    return b.toString();
  }

  double _totalVolume(List<LoggedSet> sets) =>
      sets.fold<double>(0, (double sum, LoggedSet s) => sum + s.volumeKg);

  // Null when the lifter didn't record RPE on any set.
  double? _averageRpe(List<LoggedSet> sets) {
    final List<double> values = sets
        .where((LoggedSet s) => s.rpe != null)
        .map((LoggedSet s) => s.rpe!)
        .toList();
    if (values.isEmpty) return null;
    return values.reduce((double a, double b) => a + b) / values.length;
  }

  // Same increase / maintain / deload decision the model is asked to make,
  // implemented as thresholds over average RPE. Used when there is no API key
  // or the request fails, so the card is never empty.
  CoachAdvice _offlineAdvice(List<LoggedSet> sets) {
    final double? avg = _averageRpe(sets);
    final double volume = _totalVolume(sets);
    final int prs = sets.where((LoggedSet s) => s.isPersonalBest).length;

    late final String headline;
    late final String reason;

    if (avg == null) {
      headline = 'Maintain load — log RPE next time';
      reason = 'None of these sets had an RPE recorded, so there is nothing to '
          'judge fatigue against. Repeat the same weights next session and '
          'rate each set from 6 to 10 so the trend becomes readable.';
    } else if (avg >= 9.0) {
      headline = 'Deload — fatigue is running high';
      reason = 'Your average RPE was ${avg.toStringAsFixed(1)}, which is close '
          'to failure across the whole session. Drop the working weight by '
          'about 10% next time and aim to finish sets around RPE 8.';
    } else if (avg <= 7.0) {
      headline = 'Increase weight — you had more in reserve';
      reason = 'An average RPE of ${avg.toStringAsFixed(1)} means most sets '
          'ended with several reps left. Add roughly 2.5 kg to your main lifts '
          'next session and keep the same rep targets.';
    } else {
      headline = 'Maintain load — this was a solid session';
      reason = 'An average RPE of ${avg.toStringAsFixed(1)} sits in the '
          'productive range. Repeat these weights next session and add a rep '
          'per set before you add load.';
    }

    return CoachAdvice(
      headline: headline,
      detail: '$reason\n\nYou moved ${volume.toStringAsFixed(0)} kg of total '
          'volume across ${sets.length} sets'
          '${prs > 0 ? ', including $prs personal best${prs == 1 ? '' : 's'}' : ''}'
          '.\n\n(Offline analysis — add a Gemini API key in '
          'lib/config/ai_config.dart for full AI coaching and follow-up '
          'questions.)',
      isLive: false,
    );
  }
}
