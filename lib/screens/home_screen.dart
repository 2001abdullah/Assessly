import 'package:assessly/providers/auth_provider.dart';
import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/services/exam_service.dart';
import 'package:assessly/themes/app_colors.dart';
import 'package:assessly/themes/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ExamService _examService = ExamService();

  List<Map<String, dynamic>> exams = [];

  bool isLoadingExams = true;

  @override
  void initState() {
    super.initState();
    _loadExams();
  }

  // --------------------------------------------------
  // Load Exams
  // --------------------------------------------------

  Future<void> _loadExams() async {
    try {
      final loadedExams = await _examService.getExams();

      if (!mounted) return;

      setState(() {
        exams = loadedExams;
        isLoadingExams = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isLoadingExams = false;
      });

      debugPrint('Failed to load exams: $error');
    }
  }

  // --------------------------------------------------
  // Coming Soon
  // --------------------------------------------------

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$feature is coming soon.')));
  }

  // --------------------------------------------------
  // Build
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final firstName = user?.firstName ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Assessly"),
        actions: [
          IconButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.profile),
            tooltip: 'Profile',
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --------------------------------------------------
              // Welcome
              // --------------------------------------------------

              Text(
                firstName.isEmpty
                    ? "Welcome Back👋"
                    : "Welcome back, $firstName👋",
                style: AppTextStyles.title,
              ),

              const SizedBox(height: 8),

              Text(
                "Manage your exams, answer keys and results.",
                style: AppTextStyles.bodySecondary,
              ),

              const SizedBox(height: 24),

              // --------------------------------------------------
              // Create New Exam
              // --------------------------------------------------
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.pushNamed(context, AppRoutes.createNewExam);

                    // Refresh exams after returning
                    _loadExams();
                  },
                  icon: const Icon(Icons.add),
                  label: Text("Create new exam", style: AppTextStyles.title),
                ),
              ),

              const SizedBox(height: 32),

              // --------------------------------------------------
              // Quick Actions
              // --------------------------------------------------
              Text("Quick Actions", style: AppTextStyles.title),

              const SizedBox(height: 16),

              Row(
                children: [
                  // Exams
                  Expanded(
                    child: _quickAction(
                      icon: Icons.description_outlined,
                      title: 'Exams',
                      onTap: () {
                        Navigator.pushNamed(context, AppRoutes.exams);
                      },
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Scan OMR
                  Expanded(
                    child: _quickAction(
                      icon: Icons.document_scanner_outlined,
                      title: 'Scan OMR',
                      onTap: () {
                        Navigator.pushNamed(context, AppRoutes.exams);
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  // Results
                  Expanded(
                    child: _quickAction(
                      icon: Icons.bar_chart_outlined,
                      title: 'Results',
                      onTap: () {
                        _showComingSoon(context, 'Results');
                      },
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Answer Key
                  Expanded(
                    child: _quickAction(
                      icon: Icons.key_outlined,
                      title: 'Answer Key',
                      onTap: () {
                        Navigator.pushNamed(context, AppRoutes.exams);
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // --------------------------------------------------
              // Your Exams
              // --------------------------------------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Your Exams', style: AppTextStyles.title),

                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, AppRoutes.exams);
                    },
                    child: const Text("See all"),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // --------------------------------------------------
              // Recent Exams
              // --------------------------------------------------
              _buildRecentExams(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAccountMenu(BuildContext context) async {
    final shouldLogout = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Log out'),
          onTap: () => Navigator.pop(sheetContext, true),
        ),
      ),
    );

    if (shouldLogout != true || !context.mounted) return;

    await context.read<AuthProvider>().logout();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (route) => false,
    );
  }

  // --------------------------------------------------
  // Recent Exams Widget
  // --------------------------------------------------

  Widget _buildRecentExams() {
    // Loading
    if (isLoadingExams) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 30),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.surface,
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    // No exams
    if (exams.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.surface,
        ),
        child: Column(
          children: [
            Icon(
              Icons.assignment_outlined,
              size: 48,
              color: AppColors.textSecondary,
            ),

            const SizedBox(height: 12),

            Text("No exams yet", style: AppTextStyles.body),

            const SizedBox(height: 6),

            Text(
              'Create your first exam to get started.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySecondary,
            ),
          ],
        ),
      );
    }

    // --------------------------------------------------
    // Show maximum 3 exams
    // --------------------------------------------------

    final recentExams = exams.take(3).toList();

    return Column(
      children: recentExams.map((exam) {
        final title = exam['title']?.toString() ?? 'Untitled Exam';

        final subject = exam['subject']?.toString() ?? 'No subject';

        final totalQuestions = exam['total_questions']?.toString() ?? '0';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),

            // Exam icon
            leading: CircleAvatar(
              backgroundColor: AppColors.primary,
              child: const Icon(
                Icons.description_outlined,
                color: Colors.white,
              ),
            ),

            // Exam title
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),

            // Subject + questions
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('$subject • $totalQuestions questions'),
            ),

            // Arrow
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),

            // Open exam
            onTap: () {
              Navigator.pushNamed(
                context,
                AppRoutes.examDetails,
                arguments: exam,
              );
            },
          ),
        );
      }).toList(),
    );
  }

  // --------------------------------------------------
  // Quick Action Widget
  // --------------------------------------------------

  Widget _quickAction({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 120,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30, color: AppColors.primary),

            const SizedBox(height: 12),

            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
