import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_application_mbapproject/models/nets_state.dart';
import 'package:flutter_application_mbapproject/providers/premium_provider.dart';
import 'package:flutter_application_mbapproject/services/nets_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<NetsService> netsServiceProvider =
    Provider<NetsService>((Ref ref) => NetsService());

// Drives one NETS QR payment: request the code, count it down, listen for the
// scan, then confirm the outcome.
//
// Written as a Notifier rather than the lab's StateNotifier so it matches the
// rest of this project — the lifecycle is the same, only the base class differs.
final NotifierProvider<NetsController, NetsState> netsProvider =
    NotifierProvider<NetsController, NetsState>(NetsController.new);

class NetsController extends Notifier<NetsState> {
  Timer? _ticker;
  StreamSubscription<String>? _webhook;

  // The tier this transaction is for. Held so the confirmation grants what
  // was actually paid for rather than assuming the cheaper unlock.
  PremiumTier _tier = PremiumTier.standard;

  // Notifier has no `mounted`, so disposal is tracked explicitly — the SSE
  // stream and the timer both outlive a screen the user backed out of.
  bool _disposed = false;

  @override
  NetsState build() {
    ref.onDispose(() {
      _disposed = true;
      _ticker?.cancel();
      _webhook?.cancel();
    });
    return const NetsState();
  }

  NetsService get _service => ref.read(netsServiceProvider);

  // Opens a transaction for [tier] and puts its QR on screen. The amount is
  // the tier's price, so the two tiers produce two different transactions.
  Future<void> generateQr(PremiumTier tier) async {
    _ticker?.cancel();
    _webhook?.cancel();
    _tier = tier;
    state = const NetsState(status: NetsStatus.loading);

    try {
      final NetsQrRequest req = await _service.requestQr(tier.priceSgd);
      if (_disposed) return;

      state = NetsState(
        status: NetsStatus.awaitingPayment,
        qrImage: Uint8List.fromList(req.qrImage),
        txnRef: req.txnRef,
      );

      _startCountdown(req.txnRef);
      _listenForScan(req.txnRef);
    } on NetsException catch (e) {
      if (_disposed) return;
      state = state.copyWith(status: NetsStatus.failed, message: e.message);
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        status: NetsStatus.failed,
        message: 'Could not reach NETS. $e',
      );
    }
  }

  // The QR expires after five minutes. Hitting zero is itself an outcome
  // worth confirming — the user may have paid in the last second.
  void _startCountdown(String txnRef) {
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (_disposed) return t.cancel();

      if (state.secondsLeft > 0) {
        state = state.copyWith(secondsLeft: state.secondsLeft - 1);
        return;
      }

      t.cancel();
      _confirm(txnRef);
    });
  }

  // NETS pushes events over SSE while the QR is live. The scan event is the
  // cue to stop waiting and ask for the real outcome.
  void _listenForScan(String txnRef) {
    _webhook = _service.webhookStream(txnRef).listen(
      (String chunk) {
        if (_disposed) return;
        if (chunk.contains('QR code scanned')) {
          state = state.copyWith(message: 'QR code scanned');
          _webhook?.cancel();
          _confirm(txnRef);
        }
      },
      onError: (_) {
        // A dropped stream is not a failed payment — the countdown still
        // ends in a query, so nothing is lost by ignoring it.
      },
    );
  }

  Future<void> _confirm(String txnRef) async {
    if (_disposed) return;
    state = state.copyWith(status: NetsStatus.verifying);

    try {
      final NetsPaymentResult result = await _service.checkPayment(txnRef);
      if (_disposed) return;

      if (result.isPaid) {
        // The entitlement is only granted once NETS itself confirms the
        // transaction — not when the user says they have paid.
        await ref.read(premiumProvider.notifier).activate(txnRef, _tier);
        if (_disposed) return;
        state = state.copyWith(
          status: NetsStatus.paid,
          message: result.message ?? 'Payment successful',
        );
      } else {
        state = state.copyWith(
          status: NetsStatus.failed,
          message: result.message ?? 'Payment was not completed.',
        );
      }
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        status: NetsStatus.failed,
        message: 'Could not confirm the payment. $e',
      );
    }
  }

  // Back to a clean slate so the screen can be opened again.
  void reset() {
    _ticker?.cancel();
    _webhook?.cancel();
    state = const NetsState();
  }
}
