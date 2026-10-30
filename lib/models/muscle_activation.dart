import 'package:flutter_application_mbapproject/models/exercise.dart';
import 'package:flutter_application_mbapproject/models/logged_set.dart';

// Which side of the body a muscle is drawn on.
enum BodyView { front, back }

// The muscles the body map can highlight. Deliberately coarser than real
// anatomy — these are the groups a lifter actually programmes around.
enum Muscle {
  chest,
  frontDelts,
  sideDelts,
  biceps,
  forearms,
  abs,
  quads,
  traps,
  rearDelts,
  lats,
  triceps,
  lowerBack,
  glutes,
  hamstrings,
  calves,
}

extension MuscleX on Muscle {
  String get label {
    switch (this) {
      case Muscle.chest:
        return 'Chest';
      case Muscle.frontDelts:
        return 'Front delts';
      case Muscle.sideDelts:
        return 'Side delts';
      case Muscle.biceps:
        return 'Biceps';
      case Muscle.forearms:
        return 'Forearms';
      case Muscle.abs:
        return 'Abs';
      case Muscle.quads:
        return 'Quads';
      case Muscle.traps:
        return 'Traps';
      case Muscle.rearDelts:
        return 'Rear delts';
      case Muscle.lats:
        return 'Lats';
      case Muscle.triceps:
        return 'Triceps';
      case Muscle.lowerBack:
        return 'Lower back';
      case Muscle.glutes:
        return 'Glutes';
      case Muscle.hamstrings:
        return 'Hamstrings';
      case Muscle.calves:
        return 'Calves';
    }
  }

  BodyView get view {
    switch (this) {
      case Muscle.chest:
      case Muscle.frontDelts:
      case Muscle.sideDelts:
      case Muscle.biceps:
      case Muscle.forearms:
      case Muscle.abs:
      case Muscle.quads:
        return BodyView.front;
      case Muscle.traps:
      case Muscle.rearDelts:
      case Muscle.lats:
      case Muscle.triceps:
      case Muscle.lowerBack:
      case Muscle.glutes:
      case Muscle.hamstrings:
      case Muscle.calves:
        return BodyView.back;
    }
  }
}

// How hard a muscle was worked, relative to the hardest-worked muscle in the
// same window.
enum ActivationTier { primary, secondary, minimal, none }

extension ActivationTierX on ActivationTier {
  String get label {
    switch (this) {
      case ActivationTier.primary:
        return 'Primary';
      case ActivationTier.secondary:
        return 'Secondary';
      case ActivationTier.minimal:
        return 'Minimal';
      case ActivationTier.none:
        return 'Not trained';
    }
  }
}

// One muscle's slice of the training window.
class MuscleLoad {
  const MuscleLoad({
    required this.muscle,
    required this.volumeKg,
    required this.share,
    required this.tier,
    required this.topExercise,
    required this.setCount,
  });

  final Muscle muscle;

  // Volume credited to this muscle, already scaled by how much of each
  // exercise actually targets it.
  final double volumeKg;

  // volumeKg as a fraction of the hardest-worked muscle, so the bars and the
  // body map read on the same scale.
  final double share;

  final ActivationTier tier;

  // The exercise that contributed the most to this muscle — the "Primary —
  // Bench Press" line in the breakdown.
  final String topExercise;

  final int setCount;
}

// The whole picture for one window.
class MuscleActivation {
  const MuscleActivation({
    required this.loads,
    required this.totalSets,
    required this.totalVolumeKg,
  });

  final Map<Muscle, MuscleLoad> loads;
  final int totalSets;
  final double totalVolumeKg;

  bool get isEmpty => totalSets == 0;

  // Muscles on one side of the body, hardest-worked first.
  List<MuscleLoad> forView(BodyView view) {
    final List<MuscleLoad> out = loads.values
        .where((MuscleLoad l) => l.muscle.view == view)
        .toList()
      ..sort((MuscleLoad a, MuscleLoad b) => b.volumeKg.compareTo(a.volumeKg));
    return out;
  }

  static const MuscleActivation empty = MuscleActivation(
    loads: <Muscle, MuscleLoad>{},
    totalSets: 0,
    totalVolumeKg: 0,
  );
}

// ──────────────────────────────────────────────────────────────────────
// Exercise → muscle mapping
// ──────────────────────────────────────────────────────────────────────

// Each exercise spreads its volume over several muscles. A bench press is not
// only a chest movement — the triceps and front delts do real work too, and a
// map that ignored that would tell the lifter their delts were untrained on a
// day they pressed heavy.
//
// The weights are contribution factors, not percentages, so they don't have to
// sum to 1: a set of bench credits the chest fully and the triceps at 40%.
const Map<String, Map<Muscle, double>> _byExerciseName =
    <String, Map<Muscle, double>>{
  'bench press': <Muscle, double>{
    Muscle.chest: 1.0,
    Muscle.triceps: 0.4,
    Muscle.frontDelts: 0.3,
  },
  'incline db press': <Muscle, double>{
    Muscle.chest: 1.0,
    Muscle.frontDelts: 0.45,
    Muscle.triceps: 0.3,
  },
  'chest press': <Muscle, double>{
    Muscle.chest: 1.0,
    Muscle.triceps: 0.3,
    Muscle.frontDelts: 0.25,
  },
  'cable fly': <Muscle, double>{Muscle.chest: 1.0},
  'overhead press': <Muscle, double>{
    Muscle.frontDelts: 1.0,
    Muscle.triceps: 0.4,
    Muscle.sideDelts: 0.3,
    Muscle.chest: 0.2,
  },
  'lateral raise': <Muscle, double>{
    Muscle.sideDelts: 1.0,
    Muscle.rearDelts: 0.2,
  },
  'tricep pushdown': <Muscle, double>{Muscle.triceps: 1.0},
  'bicep curl': <Muscle, double>{
    Muscle.biceps: 1.0,
    Muscle.forearms: 0.3,
  },
  'lat pulldown': <Muscle, double>{
    Muscle.lats: 1.0,
    Muscle.biceps: 0.4,
    Muscle.rearDelts: 0.2,
  },
  'pull up': <Muscle, double>{
    Muscle.lats: 1.0,
    Muscle.biceps: 0.5,
    Muscle.forearms: 0.3,
  },
  'barbell row': <Muscle, double>{
    Muscle.lats: 1.0,
    Muscle.traps: 0.6,
    Muscle.rearDelts: 0.4,
    Muscle.biceps: 0.3,
    Muscle.lowerBack: 0.3,
  },
  'seated row': <Muscle, double>{
    Muscle.traps: 1.0,
    Muscle.lats: 0.7,
    Muscle.rearDelts: 0.4,
    Muscle.biceps: 0.3,
  },
  'squat': <Muscle, double>{
    Muscle.quads: 1.0,
    Muscle.glutes: 0.6,
    Muscle.hamstrings: 0.3,
    Muscle.lowerBack: 0.3,
    Muscle.abs: 0.2,
  },
  'leg press': <Muscle, double>{
    Muscle.quads: 1.0,
    Muscle.glutes: 0.5,
    Muscle.hamstrings: 0.2,
  },
  'leg extension': <Muscle, double>{Muscle.quads: 1.0},
  'romanian deadlift': <Muscle, double>{
    Muscle.hamstrings: 1.0,
    Muscle.glutes: 0.7,
    Muscle.lowerBack: 0.5,
    Muscle.traps: 0.2,
  },
  'calf raise': <Muscle, double>{Muscle.calves: 1.0},
  'plank': <Muscle, double>{Muscle.abs: 1.0},
};

// Fallback for exercises the user created themselves, which won't be in the
// table above. Uses whatever category they picked in the Library.
const Map<String, Map<Muscle, double>> _byCategory =
    <String, Map<Muscle, double>>{
  'chest': <Muscle, double>{
    Muscle.chest: 1.0,
    Muscle.triceps: 0.3,
    Muscle.frontDelts: 0.25,
  },
  'back': <Muscle, double>{
    Muscle.lats: 1.0,
    Muscle.traps: 0.5,
    Muscle.biceps: 0.3,
  },
  'legs': <Muscle, double>{
    Muscle.quads: 1.0,
    Muscle.hamstrings: 0.6,
    Muscle.glutes: 0.6,
  },
  'shoulders': <Muscle, double>{
    Muscle.frontDelts: 0.8,
    Muscle.sideDelts: 0.8,
    Muscle.rearDelts: 0.4,
    Muscle.triceps: 0.2,
  },
  'arms': <Muscle, double>{
    Muscle.biceps: 0.6,
    Muscle.triceps: 0.6,
    Muscle.forearms: 0.3,
  },
  'core': <Muscle, double>{Muscle.abs: 1.0},
};

// Turns a window of logged sets into a per-muscle picture.
//
// [exercisesById] is used to look up each set's category so custom exercises
// still land somewhere sensible; sets whose exercise has since been deleted
// fall back to matching on the denormalised exercise name.
MuscleActivation computeMuscleActivation({
  required List<LoggedSet> sets,
  required Map<String, Exercise> exercisesById,
}) {
  if (sets.isEmpty) return MuscleActivation.empty;

  final Map<Muscle, double> volume = <Muscle, double>{};
  final Map<Muscle, int> setCounts = <Muscle, int>{};
  // Per muscle, how much each exercise contributed — used to name the top one.
  final Map<Muscle, Map<String, double>> contributors =
      <Muscle, Map<String, double>>{};

  double totalVolume = 0;

  for (final LoggedSet s in sets) {
    totalVolume += s.volumeKg;

    final Map<Muscle, double>? weights = _weightsFor(s, exercisesById);
    if (weights == null) continue;

    weights.forEach((Muscle m, double factor) {
      final double credited = s.volumeKg * factor;
      volume[m] = (volume[m] ?? 0) + credited;
      setCounts[m] = (setCounts[m] ?? 0) + 1;
      contributors.putIfAbsent(m, () => <String, double>{});
      contributors[m]![s.exerciseName] =
          (contributors[m]![s.exerciseName] ?? 0) + credited;
    });
  }

  if (volume.isEmpty) {
    return MuscleActivation(
      loads: const <Muscle, MuscleLoad>{},
      totalSets: sets.length,
      totalVolumeKg: totalVolume,
    );
  }

  final double peak =
      volume.values.reduce((double a, double b) => a > b ? a : b);

  final Map<Muscle, MuscleLoad> loads = <Muscle, MuscleLoad>{};
  volume.forEach((Muscle m, double v) {
    final double share = peak <= 0 ? 0 : v / peak;

    // Tiers are relative to the hardest-worked muscle, so the map still reads
    // sensibly whether the window holds one session or fifty.
    final ActivationTier tier = share >= 0.6
        ? ActivationTier.primary
        : share >= 0.25
            ? ActivationTier.secondary
            : ActivationTier.minimal;

    // Exercise that put the most volume through this muscle.
    String top = '';
    double topValue = -1;
    contributors[m]?.forEach((String name, double value) {
      if (value > topValue) {
        topValue = value;
        top = name;
      }
    });

    loads[m] = MuscleLoad(
      muscle: m,
      volumeKg: v,
      share: share,
      tier: tier,
      topExercise: top,
      setCount: setCounts[m] ?? 0,
    );
  });

  return MuscleActivation(
    loads: loads,
    totalSets: sets.length,
    totalVolumeKg: totalVolume,
  );
}

// Name match first (most precise), then the exercise's category, then the
// name-derived category as a last resort.
Map<Muscle, double>? _weightsFor(
  LoggedSet s,
  Map<String, Exercise> exercisesById,
) {
  final String name = s.exerciseName.trim().toLowerCase();
  if (_byExerciseName.containsKey(name)) return _byExerciseName[name];

  final Exercise? exercise = exercisesById[s.exerciseId];
  if (exercise != null) {
    final Map<Muscle, double>? byCat =
        _byCategory[exercise.category.trim().toLowerCase()];
    if (byCat != null) return byCat;
  }

  // Unknown exercise with no surviving library entry — better to leave it out
  // than to guess and colour a muscle that was never worked.
  return null;
}
