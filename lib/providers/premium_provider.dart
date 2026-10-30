import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The two unlocks a lifter can buy.
//
// Both are single payments — SetLog never bills monthly, which is the whole
// pitch against the subscription apps — so the tiers differ by how much
// coaching they buy rather than by how long they last. Plus raises the token
// ceiling on the Gemini reply, so it returns a genuinely longer analysis
// rather than the same one behind a bigger price.
enum PremiumTier {
  standard(
    id: 'standard',
    label: 'Premium',
    priceSgd: 4.99,
    tagline: 'Unlimited coach follow-ups',
    coachTokenBudget: 400,
  ),
  plus(
    id: 'plus',
    label: 'Premium Plus',
    priceSgd: 8.99,
    tagline: 'Everything in Premium, plus longer coaching reports',
    coachTokenBudget: 900,
  );

  const PremiumTier({
    required this.id,
    required this.label,
    required this.priceSgd,
    required this.tagline,
    required this.coachTokenBudget,
  });

  final String id;
  final String label;
  final double priceSgd;
  final String tagline;
  final int coachTokenBudget;

  String get priceLabel => 'S\$${priceSgd.toStringAsFixed(2)}';

  // Unknown or missing ids fall back to the cheaper tier rather than
  // silently handing out the more expensive one.
  static PremiumTier fromId(String? id) => values.firstWhere(
        (PremiumTier t) => t.id == id,
        orElse: () => standard,
      );
}

// Which tier the upgrade screen has selected. Changing it re-requests the QR,
// because the amount is part of the NETS transaction itself.
final StateProvider<PremiumTier> selectedTierProvider =
    StateProvider<PremiumTier>((Ref ref) => PremiumTier.standard);

// The tier actually paid for, or null while the user is still on the free
// tier. Read by the coach to decide how long an answer it may give.
final FutureProvider<PremiumTier?> purchasedTierProvider =
    FutureProvider<PremiumTier?>((Ref ref) async {
  final bool active = await ref.watch(premiumProvider.future);
  if (!active) return null;
  return ref.read(premiumProvider.notifier).purchasedTier();
});

// Token ceiling for one coach reply. Free and Premium share the standard
// budget; Plus buys the longer report.
final FutureProvider<int> coachTokenBudgetProvider =
    FutureProvider<int>((Ref ref) async {
  final PremiumTier? tier = await ref.watch(purchasedTierProvider.future);
  return (tier ?? PremiumTier.standard).coachTokenBudget;
});

// Whether this device has an active SetLog Premium unlock.
//
// Stored locally rather than in Firestore because it is a device-level
// entitlement in this build; a production app would record the NETS
// transaction server-side so the purchase followed the account.
final AsyncNotifierProvider<PremiumController, bool> premiumProvider =
    AsyncNotifierProvider<PremiumController, bool>(PremiumController.new);

class PremiumController extends AsyncNotifier<bool> {
  static const String _key = 'premium_active';
  static const String _refKey = 'premium_reference';
  static const String _tierKey = 'premium_tier';

  @override
  Future<bool> build() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  // Called once the NETS payment is confirmed — never before.
  Future<void> activate(String reference, PremiumTier tier) async {
    state = const AsyncData<bool>(true);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    await prefs.setString(_refKey, reference);
    await prefs.setString(_tierKey, tier.id);
  }

  // Lets the unlock be reset, so the payment flow can be demonstrated more
  // than once without reinstalling.
  Future<void> cancel() async {
    state = const AsyncData<bool>(false);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, false);
    await prefs.remove(_refKey);
    await prefs.remove(_tierKey);
  }

  Future<String?> reference() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refKey);
  }

  Future<PremiumTier?> purchasedTier() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? id = prefs.getString(_tierKey);
    return id == null ? null : PremiumTier.fromId(id);
  }
}
