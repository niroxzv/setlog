import 'package:flutter/material.dart';
import 'package:flutter_application_mbapproject/screens/history_screen.dart';
import 'package:flutter_application_mbapproject/screens/library_screen.dart';
import 'package:flutter_application_mbapproject/screens/profile_screen.dart';
import 'package:flutter_application_mbapproject/screens/stats_screen.dart';
import 'package:flutter_application_mbapproject/screens/workout_screen.dart';

// Five-tab home shell. IndexedStack keeps every tab's State alive on switch.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainScreen> {
  int _currentIndex = 0;

  // Tabs are `const` so Dart can keep a single instance — small perf win
  // since this list is rebuilt on every parent rebuild.
  static const List<Widget> _tabs = <Widget>[
    WorkoutScreen(),
    LibraryScreen(),
    HistoryScreen(),
    StatsScreen(),
    ProfileScreen(),
  ];

  static const List<BottomNavigationBarItem> _navItems =
      <BottomNavigationBarItem>[
    BottomNavigationBarItem(
      icon: Icon(Icons.fitness_center_outlined),
      activeIcon: Icon(Icons.fitness_center),
      label: 'Workout',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.library_books_outlined),
      activeIcon: Icon(Icons.library_books),
      label: 'Library',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.history_outlined),
      activeIcon: Icon(Icons.history),
      label: 'History',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.bar_chart_outlined),
      activeIcon: Icon(Icons.bar_chart),
      label: 'Stats',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.person_outline),
      activeIcon: Icon(Icons.person),
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack swaps the visible child via `index` — all children stay
      // mounted, so they retain their State.
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (int index) => setState(() => _currentIndex = index),
        items: _navItems,
      ),
    );
  }
}
