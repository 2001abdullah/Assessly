import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/student_provider.dart';
import '../../widgets/app_widgets.dart';
import 'student_home_screen.dart' show MyResultCard;

/// All of the student's published results, filterable by class.
class MyResultsScreen extends StatefulWidget {
  const MyResultsScreen({super.key});

  @override
  State<MyResultsScreen> createState() => _MyResultsScreenState();
}

class _MyResultsScreenState extends State<MyResultsScreen> {
  String? _classId;

  @override
  Widget build(BuildContext context) {
    final student = context.watch<StudentProvider>();
    final classes = {
      for (final r in student.results)
        r['class_id'].toString(): r['class_name'].toString(),
    };
    final shown = student.results
        .where((r) => _classId == null || r['class_id'].toString() == _classId)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('My results')),
      body: RefreshIndicator(
        onRefresh: student.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (classes.length > 1) ...[
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: _classId == null,
                        onSelected: (_) => setState(() => _classId = null),
                      ),
                    ),
                    for (final e in classes.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(e.value),
                          selected: _classId == e.key,
                          onSelected: (_) => setState(() => _classId = e.key),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (student.isLoading && !student.hasLoaded)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (student.error != null && !student.hasLoaded)
              ErrorState(message: student.error!, onRetry: student.refresh)
            else if (shown.isEmpty)
              const EmptyState(
                icon: Icons.fact_check_outlined,
                title: 'No results yet',
                message: 'Results show up here as soon as your teacher publishes them.',
              )
            else
              for (final r in shown) MyResultCard(data: r),
          ],
        ),
      ),
    );
  }
}
