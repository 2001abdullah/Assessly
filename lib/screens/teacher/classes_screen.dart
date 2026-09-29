import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/class_provider.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_widgets.dart';
import 'teacher_home_screen.dart' show ClassCard;

/// The teacher's classes (Classes tab), with a button to create one.
class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ClassProvider>().load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ClassProvider>();
    final classes = provider.classes;

    return Scaffold(
      appBar: AppBar(title: const Text('Classes')),
      floatingActionButton: FloatingActionButton.extended(
        // Unique: the tabs stay mounted side by side in the home shell.
        heroTag: 'fab-classes',
        onPressed: () => Navigator.pushNamed(context, AppRoutes.createClass),
        icon: const Icon(Icons.add),
        label: const Text('New class'),
      ),
      body: RefreshIndicator(
        onRefresh: provider.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            if (provider.isLoading && !provider.hasLoaded)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (provider.error != null && classes.isEmpty)
              ErrorState(message: provider.error!, onRetry: provider.refresh)
            else if (classes.isEmpty)
              const EmptyState(
                icon: Icons.groups_2_outlined,
                title: 'No classes yet',
                message: 'Create a class, share its join code with students, then take attendance and publish results.',
              )
            else
              for (final c in classes) ...[
                ClassCard(data: c),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}
