import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import 'exam_list_screen.dart';
import 'profile_screen.dart';
import 'results_hub_screen.dart';
import 'student/my_attendance_screen.dart';
import 'student/my_results_screen.dart';
import 'student/performance_screen.dart';
import 'student/student_home_screen.dart';
import 'teacher/classes_screen.dart';
import 'teacher/teacher_home_screen.dart';

/// The signed-in app: a bottom navigation bar over the role's main screens.
///
/// Teacher: Home, Classes, Exams, Results, Profile.
/// Student: Home, Results, Progress, Attendance, Profile.
///
/// Tabs keep their state (IndexedStack). Screens inside a tab can switch tabs
/// with `ShellScope.of(context)?.goTo(index)`.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon, this.screen);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

const _teacherTabs = [
  _Tab(
    'Home',
    Icons.space_dashboard_outlined,
    Icons.space_dashboard_rounded,
    TeacherHomeScreen(),
  ),
  _Tab(
    'Classes',
    Icons.groups_2_outlined,
    Icons.groups_2_rounded,
    ClassesScreen(),
  ),
  _Tab(
    'Exams',
    Icons.assignment_outlined,
    Icons.assignment_rounded,
    ExamListScreen(),
  ),
  _Tab(
    'Results',
    Icons.insights_outlined,
    Icons.insights_rounded,
    ResultsHubScreen(),
  ),
  _Tab(
    'Profile',
    Icons.person_outline_rounded,
    Icons.person_rounded,
    ProfileScreen(),
  ),
];

const _studentTabs = [
  _Tab('Home', Icons.home_outlined, Icons.home_rounded, StudentHomeScreen()),
  _Tab(
    'Results',
    Icons.fact_check_outlined,
    Icons.fact_check_rounded,
    MyResultsScreen(),
  ),
  _Tab(
    'Progress',
    Icons.insights_outlined,
    Icons.insights_rounded,
    PerformanceScreen(),
  ),
  _Tab(
    'Attendance',
    Icons.event_available_outlined,
    Icons.event_available_rounded,
    MyAttendanceScreen(),
  ),
  _Tab(
    'Profile',
    Icons.person_outline_rounded,
    Icons.person_rounded,
    ProfileScreen(),
  ),
];

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationProvider>().start();
    });
  }

  void _goTo(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final student = context.select<AuthProvider, bool>((a) => a.isStudent);
    final tabs = student ? _studentTabs : _teacherTabs;
    final index = _index.clamp(0, tabs.length - 1);

    return ShellScope(
      goTo: _goTo,
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: [for (final t in tabs) t.screen],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: _goTo,
          destinations: [
            for (final t in tabs)
              NavigationDestination(
                icon: Icon(t.icon),
                selectedIcon: Icon(t.selectedIcon),
                label: t.label,
              ),
          ],
        ),
      ),
    );
  }
}

/// Lets a tab's content switch to another tab.
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.goTo, required super.child});

  final void Function(int index) goTo;

  static ShellScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope oldWidget) => false;
}

/// Tab positions, for [ShellScope.goTo].
abstract final class TeacherTab {
  static const home = 0, classes = 1, exams = 2, results = 3, profile = 4;
}

abstract final class StudentTab {
  static const home = 0, results = 1, progress = 2, attendance = 3, profile = 4;
}
