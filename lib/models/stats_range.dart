// How far back the Stats screens look. Lives in its own file because both
// the Progress screen and the Muscle activation screen key their data off it.
enum StatsRange { fourWeeks, threeMonths, sixMonths }

extension StatsRangeX on StatsRange {
  String get label {
    switch (this) {
      case StatsRange.fourWeeks:
        return '4w';
      case StatsRange.threeMonths:
        return '3m';
      case StatsRange.sixMonths:
        return '6m';
    }
  }

  // Number of buckets drawn in the volume chart.
  int get buckets {
    switch (this) {
      case StatsRange.fourWeeks:
        return 4;
      case StatsRange.threeMonths:
        return 3;
      case StatsRange.sixMonths:
        return 6;
    }
  }

  // 4w is charted week-by-week; the longer ranges would be unreadable at
  // weekly resolution, so they roll up into months.
  bool get isWeekly => this == StatsRange.fourWeeks;

  String get windowLabel {
    switch (this) {
      case StatsRange.fourWeeks:
        return 'last 4 weeks';
      case StatsRange.threeMonths:
        return 'last 3 months';
      case StatsRange.sixMonths:
        return 'last 6 months';
    }
  }

  // Oldest date still inside the window.
  DateTime get cutoff {
    final DateTime now = DateTime.now();
    switch (this) {
      case StatsRange.fourWeeks:
        return now.subtract(const Duration(days: 28));
      case StatsRange.threeMonths:
        return DateTime(now.year, now.month - 3, now.day);
      case StatsRange.sixMonths:
        return DateTime(now.year, now.month - 6, now.day);
    }
  }
}
