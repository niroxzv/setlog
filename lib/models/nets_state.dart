import 'dart:typed_data';

// Where a NETS QR payment has got to.
//
// An enum rather than the loose strings used in the lab, so a typo in a status
// name is a compile error instead of a branch that silently never runs.
enum NetsStatus {
  // Nothing requested yet.
  idle,
  // Asking NETS to open the transaction.
  loading,
  // QR is on screen, waiting for the user to scan and pay.
  awaitingPayment,
  // NETS told us the code was scanned; confirming the outcome.
  verifying,
  paid,
  failed,
}

class NetsState {
  const NetsState({
    this.status = NetsStatus.idle,
    this.qrImage,
    this.txnRef,
    this.message,
    this.secondsLeft = validitySeconds,
  });

  // A NETS QR is valid for five minutes.
  static const int validitySeconds = 300;

  final NetsStatus status;
  final Uint8List? qrImage;
  final String? txnRef;

  // Whatever NETS last told us — shown verbatim so a failure reads as the
  // gateway's own words rather than something the app invented.
  final String? message;

  final int secondsLeft;

  bool get isBusy =>
      status == NetsStatus.loading || status == NetsStatus.verifying;

  bool get hasExpired =>
      secondsLeft == 0 && status == NetsStatus.awaitingPayment;

  String get countdown {
    final int m = secondsLeft ~/ 60;
    final int s = secondsLeft % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  NetsState copyWith({
    NetsStatus? status,
    Uint8List? qrImage,
    String? txnRef,
    String? message,
    int? secondsLeft,
  }) {
    return NetsState(
      status: status ?? this.status,
      qrImage: qrImage ?? this.qrImage,
      txnRef: txnRef ?? this.txnRef,
      message: message ?? this.message,
      secondsLeft: secondsLeft ?? this.secondsLeft,
    );
  }
}
