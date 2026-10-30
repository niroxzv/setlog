import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/providers/ai_provider.dart';
import 'package:flutter_application_mbapproject/providers/premium_provider.dart';
import 'package:flutter_application_mbapproject/screens/premium_screen.dart';
import 'package:flutter_application_mbapproject/services/ai_coach_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_application_mbapproject/theme/app_theme.dart';

// The proposal's Applied AI feature, on the workout summary screen.
//
// Collapsed it shows a single verdict line. Tapping the card pulls it down to
// reveal the full analysis and a follow-up box the lifter can keep asking
// questions in — each answer is generated with the session's real sets as
// context.
class AiCoachCard extends ConsumerStatefulWidget {
  const AiCoachCard({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<AiCoachCard> createState() => _AiCoachCardState();
}

class _AiCoachCardState extends ConsumerState<AiCoachCard> {
  bool _expanded = false;
  final TextEditingController _questionController = TextEditingController();

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String q = _questionController.text.trim();
    if (q.isEmpty) return;
    _questionController.clear();
    await ref.read(coachChatProvider(widget.sessionId).notifier).ask(q);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<CoachAdvice> advice =
        ref.watch(coachAdviceProvider(widget.sessionId));

    return Container(
      decoration: BoxDecoration(
        color: theme.setLog.focusPanel,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header is the tap target for the pull-down.
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Color.fromARGB(255, 5, 103, 194),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Text(
                              'AI Coach',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Honest label: says whether this came from the
                            // model or the on-device fallback.
                            if (advice.hasValue)
                              _Tag(
                                label: advice.value!.isLive
                                    ? 'Gemini'
                                    : 'Offline',
                                highlighted: advice.value!.isLive,
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        advice.when(
                          loading: () => const Text(
                            'Analysing your session…',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                          error: (Object e, _) => const Text(
                            'Coach unavailable right now.',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                          data: (CoachAdvice a) => Text(
                            a.headline,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Arrow rotates to signal the pull-down state.
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded body: full analysis + follow-up thread.
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _ExpandedBody(
              sessionId: widget.sessionId,
              advice: advice,
              controller: _questionController,
              onSend: _send,
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }
}

class _ExpandedBody extends ConsumerWidget {
  // Free follow-up questions before SetLog Premium is required.
  static const int _freeFollowUps = 1;

  const _ExpandedBody({
    required this.sessionId,
    required this.advice,
    required this.controller,
    required this.onSend,
  });

  final String sessionId;
  final AsyncValue<CoachAdvice> advice;
  final TextEditingController controller;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CoachChatState chat = ref.watch(coachChatProvider(sessionId));
    final bool isPremium = ref.watch(premiumProvider).value ?? false;

    // Everyone gets one follow-up before the paywall. Asking a single question
    // is what makes the feature legible — a locked box the lifter has never
    // used is a worse pitch for Premium than one they've just felt the value
    // of. Counted from the thread itself, so it survives leaving the screen.
    final int asked =
        chat.messages.where((CoachMessage m) => m.fromUser).length;
    final bool canAsk = isPremium || asked < _freeFollowUps;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Divider(color: Colors.white.withValues(alpha: 0.12), height: 20),

          advice.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white70),
              ),
            ),
            // coachAdviceProvider caches its result, so a one-off failure
            // would otherwise stick until the app restarts. Invalidating the
            // family entry re-runs the read and the API call.
            error: (Object e, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$e',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () =>
                      ref.invalidate(coachAdviceProvider(sessionId)),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Try again'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            data: (CoachAdvice a) => Text(
              a.detail,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),

          // Follow-up conversation.
          if (chat.messages.isNotEmpty) ...<Widget>[
            Divider(color: Colors.white.withValues(alpha: 0.12), height: 24),
            ...chat.messages.map((CoachMessage m) => _Bubble(message: m)),
          ],

          if (chat.isThinking)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    height: 12,
                    width: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white54),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Coach is thinking…',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // The opening analysis and the first follow-up are free; asking
          // beyond that is the Premium feature the NETS payment unlocks.
          if (!canAsk)
            _UpgradePrompt(
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const PremiumScreen(),
                ),
              ),
            )
          else
          // Ask box.
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !chat.isThinking,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Ask the coach a follow-up…',
                    hintStyle: const TextStyle(
                        color: Colors.white38, fontSize: 13),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: chat.isThinking ? null : onSend,
                icon: const Icon(Icons.arrow_upward, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),

          // Says what the free allowance is before it's spent, so hitting the
          // paywall isn't a surprise.
          if (canAsk && !isPremium) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              '${_freeFollowUps - asked} free question included with this '
              'session.',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],

          const SizedBox(height: 6),
          // Standard disclaimer — the coach is guidance, not medical advice.
          const Text(
            'AI-generated guidance. Not medical advice.',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// Shown in place of the ask box for free users.
class _UpgradePrompt extends StatelessWidget {
  const _UpgradePrompt({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.lock_outline, color: Colors.white54, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'That was your free question. Keep asking with SetLog Premium',
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ),
            Text(
              'Upgrade',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// One turn in the follow-up thread.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final CoachMessage message;

  @override
  Widget build(BuildContext context) {
    final bool mine = message.fromUser;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: mine
              ? Theme.of(context).colorScheme.primary
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: mine ? Colors.white : Colors.white70,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

// Small pill next to the "AI Coach" title.
class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.highlighted});
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: highlighted
            ? Theme.of(context).colorScheme.primary
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
