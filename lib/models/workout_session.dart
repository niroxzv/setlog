import 'package:cloud_firestore/cloud_firestore.dart';

// Broad training split. Drives the History filter chips and the coloured
// category dot on each session card.
enum SessionCategory { push, pull, legs, other }

// Parses the Firestore string back into the enum, defaulting to `other`
// so an unexpected value can never crash the list.
SessionCategory categoryFromName(String? name) {
  return SessionCategory.values.firstWhere(
    (SessionCategory c) => c.name == name,
    orElse: () => SessionCategory.other,
  );
}

// What the History screen is currently filtered to.
//
// Deliberately richer than a nullable SessionCategory, because the chips
// exercise two different Firestore query shapes:
//   • push / pull / legs  ->  where('category', isEqualTo: …)
//   • upperBody           ->  where('category', whereIn: [push, pull])
// Both run on the server; the enum is what picks which query to build.
enum HistoryFilter { all, push, pull, legs, upperBody }

extension HistoryFilterX on HistoryFilter {
  String get label {
    switch (this) {
      case HistoryFilter.all:
        return 'All';
      case HistoryFilter.push:
        return 'Push';
      case HistoryFilter.pull:
        return 'Pull';
      case HistoryFilter.legs:
        return 'Legs';
      case HistoryFilter.upperBody:
        return 'Upper body';
    }
  }

  // The single category this filter maps to, or null when it doesn't map to
  // exactly one (All, Upper body).
  SessionCategory? get singleCategory {
    switch (this) {
      case HistoryFilter.push:
        return SessionCategory.push;
      case HistoryFilter.pull:
        return SessionCategory.pull;
      case HistoryFilter.legs:
        return SessionCategory.legs;
      case HistoryFilter.all:
      case HistoryFilter.upperBody:
        return null;
    }
  }

  // Several accepted values for the one `category` field.
  List<SessionCategory>? get multipleCategories {
    return this == HistoryFilter.upperBody
        ? const <SessionCategory>[SessionCategory.push, SessionCategory.pull]
        : null;
  }
}

// One workout session — the `sessions` collection.
//
// The Part 1 data dictionary denormalised session_name / session_date /
// session_duration onto every row of the sets table. In Firestore those are
// normalised into their own collection so History can query sessions
// directly instead of scanning every set. The data captured is identical.
class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.userId,
    required this.name,
    required this.category,
    required this.date,
    this.durationSeconds = 0,
    this.totalVolumeKg = 0,
    this.setCount = 0,
    this.exerciseCount = 0,
    this.hasPr = false,
    this.isActive = false,
  });

  final String id;
  final String userId;
  final String name; // e.g. "Push A"
  final SessionCategory category;
  final DateTime date;
  final int durationSeconds;
  final double totalVolumeKg;
  final int setCount;
  final int exerciseCount;
  final bool hasPr;
  final bool isActive; // true while the workout is still in progress

  factory WorkoutSession.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return WorkoutSession(
      id: doc.id,
      userId: d['user_id'] as String? ?? '',
      name: d['session_name'] as String? ?? 'Session',
      category: categoryFromName(d['category'] as String?),
      // serverTimestamp() is briefly null on the local echo of a write, so
      // fall back to now rather than throwing.
      date: (d['session_date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      durationSeconds: d['session_duration'] as int? ?? 0,
      totalVolumeKg: (d['total_volume_kg'] as num?)?.toDouble() ?? 0,
      setCount: d['set_count'] as int? ?? 0,
      exerciseCount: d['exercise_count'] as int? ?? 0,
      hasPr: d['has_pr'] as bool? ?? false,
      isActive: d['is_active'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'user_id': userId,
      'session_name': name,
      'category': category.name,
      'session_date': Timestamp.fromDate(date),
      'session_duration': durationSeconds,
      'total_volume_kg': totalVolumeKg,
      'set_count': setCount,
      'exercise_count': exerciseCount,
      'has_pr': hasPr,
      'is_active': isActive,
      'created_at': FieldValue.serverTimestamp(),
    };
  }
}
