// Placeholder data for the home dashboard, history, library, and stats
// screens until Firestore is wired up.

import 'package:flutter/material.dart';

class LoggedSet {
  const LoggedSet({
    required this.exercise,
    required this.weightKg,
    required this.reps,
    required this.rpe,
  });

  final String exercise;
  final double weightKg;
  final int reps;
  final double rpe; // 1.0-10.0 in 0.5 steps

  String get displayLine =>
      '$exercise — ${weightKg.toStringAsFixed(1)}kg × $reps @ RPE ${rpe.toStringAsFixed(1)}';
}

// Broad muscle-group split used for the History filter chips + the coloured
// dot on each session card (Push=blue, Pull=green, Legs=orange).
enum SessionCategory { push, pull, legs, other }

class PastSession {
  const PastSession({
    required this.title,
    required this.date,
    required this.totalVolumeKg,
    required this.setCount,
    this.exerciseCount = 0,
    this.category = SessionCategory.other,
    this.hasPr = false,
  });

  final String title;
  final DateTime date;
  final double totalVolumeKg;
  final int setCount;
  final int exerciseCount;
  final SessionCategory category;
  final bool hasPr;
}

class ExerciseCategory {
  const ExerciseCategory({
    required this.name,
    required this.exerciseCount,
    required this.icon,
  });

  final String name;
  final int exerciseCount;
  final IconData icon;
}

const List<LoggedSet> currentSessionSets = <LoggedSet>[
  LoggedSet(exercise: 'Bench Press', weightKg: 80, reps: 8, rpe: 7),
  LoggedSet(exercise: 'Bench Press', weightKg: 82.5, reps: 8, rpe: 7.5),
  LoggedSet(exercise: 'Bench Press', weightKg: 82.5, reps: 7, rpe: 8),
  LoggedSet(exercise: 'Incline DB Press', weightKg: 30, reps: 10, rpe: 7),
  LoggedSet(exercise: 'Incline DB Press', weightKg: 30, reps: 10, rpe: 7.5),
  LoggedSet(exercise: 'Cable Fly', weightKg: 17.5, reps: 12, rpe: 8),
];

final List<PastSession> pastSessions = <PastSession>[
  PastSession(
    title: 'Push Day',
    date: DateTime.now(),
    totalVolumeKg: 4320,
    setCount: 9,
    exerciseCount: 3,
    category: SessionCategory.push,
    hasPr: true,
  ),
  PastSession(
    title: 'Pull Day',
    date: DateTime.now().subtract(const Duration(days: 2)),
    totalVolumeKg: 6840,
    setCount: 11,
    exerciseCount: 3,
    category: SessionCategory.pull,
  ),
  PastSession(
    title: 'Legs Day',
    date: DateTime.now().subtract(const Duration(days: 4)),
    totalVolumeKg: 14290,
    setCount: 10,
    exerciseCount: 3,
    category: SessionCategory.legs,
  ),
  PastSession(
    title: 'Push Day',
    date: DateTime.now().subtract(const Duration(days: 6)),
    totalVolumeKg: 4240,
    setCount: 7,
    exerciseCount: 2,
    category: SessionCategory.push,
  ),
  PastSession(
    title: 'Pull Day',
    date: DateTime.now().subtract(const Duration(days: 9)),
    totalVolumeKg: 7280,
    setCount: 8,
    exerciseCount: 3,
    category: SessionCategory.pull,
  ),
];

const List<ExerciseCategory> exerciseCategories = <ExerciseCategory>[
  ExerciseCategory(name: 'Chest', exerciseCount: 12, icon: Icons.fitness_center),
  ExerciseCategory(name: 'Back', exerciseCount: 14, icon: Icons.rowing),
  ExerciseCategory(name: 'Shoulders', exerciseCount: 9, icon: Icons.accessibility_new),
  ExerciseCategory(name: 'Arms', exerciseCount: 11, icon: Icons.sports_martial_arts),
  ExerciseCategory(name: 'Legs', exerciseCount: 16, icon: Icons.directions_run),
  ExerciseCategory(name: 'Core', exerciseCount: 8, icon: Icons.self_improvement),
];

const List<String> exerciseChoices = <String>[
  'Bench Press',
  'Incline DB Press',
  'Cable Fly',
  'Overhead Press',
  'Lateral Raise',
  'Squat',
  'Romanian Deadlift',
  'Leg Press',
  'Pull Up',
  'Barbell Row',
  'Lat Pulldown',
  'Bicep Curl',
  'Tricep Pushdown',
  'Plank',
];
