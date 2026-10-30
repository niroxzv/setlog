import 'package:flutter_application_mbapproject/models/logged_set.dart';
import 'package:flutter_application_mbapproject/models/workout_session.dart';
import 'package:flutter_application_mbapproject/providers/firestore_provider.dart';
import 'package:flutter_application_mbapproject/providers/premium_provider.dart';
import 'package:flutter_application_mbapproject/services/ai_coach_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<AiCoachService> aiCoachServiceProvider =
    Provider<AiCoachService>((Ref ref) => AiCoachService());

// The opening verdict for one session. FutureProvider.family keys the result
// by session id, and Riverpod caches it — reopening the same summary does not
// spend another API call.
final FutureProviderFamily<CoachAdvice, String> coachAdviceProvider =
    FutureProvider.family<CoachAdvice, String>((Ref ref, String sessionId) async {
  final WorkoutSession? session =
      await ref.watch(sessionDetailProvider(sessionId).future);
  final List<LoggedSet> sets =
      await ref.watch(sessionSetsProvider(sessionId).future);

  // Premium Plus raises the token ceiling, so the same session comes back
  // with a fuller analysis rather than the same text behind a bigger price.
  final int budget = await ref.watch(coachTokenBudgetProvider.future);

  return ref.watch(aiCoachServiceProvider).analyseSession(
        session: session,
        sets: sets,
        maxTokens: budget,
      );
});

// ────────────────────────────────────────────────────────────────
// Follow-up conversation
// ────────────────────────────────────────────────────────────────

class CoachChatState {
  const CoachChatState({
    this.messages = const <CoachMessage>[],
    this.isThinking = false,
  });

  final List<CoachMessage> messages;
  final bool isThinking;

  CoachChatState copyWith({
    List<CoachMessage>? messages,
    bool? isThinking,
  }) {
    return CoachChatState(
      messages: messages ?? this.messages,
      isThinking: isThinking ?? this.isThinking,
    );
  }
}

// Holds the follow-up thread for one session. Keyed by session id so two
// different workouts keep separate conversations.
final NotifierProviderFamily<CoachChatController, CoachChatState, String>
    coachChatProvider =
    NotifierProvider.family<CoachChatController, CoachChatState, String>(
        CoachChatController.new);

class CoachChatController
    extends FamilyNotifier<CoachChatState, String> {
  @override
  CoachChatState build(String sessionId) => const CoachChatState();

  Future<void> ask(String question) async {
    final String trimmed = question.trim();
    if (trimmed.isEmpty || state.isThinking) return;

    // Show the user's message immediately, then the typing indicator.
    final List<CoachMessage> history = state.messages;
    state = state.copyWith(
      messages: <CoachMessage>[
        ...history,
        CoachMessage(text: trimmed, fromUser: true),
      ],
      isThinking: true,
    );

    final WorkoutSession? session =
        await ref.read(sessionDetailProvider(arg).future);
    final List<LoggedSet> sets =
        await ref.read(sessionSetsProvider(arg).future);

    final int budget = await ref.read(coachTokenBudgetProvider.future);

    final String answer =
        await ref.read(aiCoachServiceProvider).askFollowUp(
              session: session,
              sets: sets,
              history: history,
              question: trimmed,
              maxTokens: budget,
            );

    state = state.copyWith(
      messages: <CoachMessage>[
        ...state.messages,
        CoachMessage(text: answer, fromUser: false),
      ],
      isThinking: false,
    );
  }
}
