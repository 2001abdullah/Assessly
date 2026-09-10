import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/services/exam_service.dart';
import 'package:flutter/material.dart';
import 'package:assessly/themes/app_text_styles.dart';
import 'package:assessly/screens/exam_details_screen.dart';

class CreateExamScreen extends StatefulWidget {
  const CreateExamScreen({super.key});

  @override
  State<CreateExamScreen> createState() => _CreateExamScreenState();
}

class _CreateExamScreenState extends State<CreateExamScreen> {
  final _formKey = GlobalKey<FormState>();

  final titleController=TextEditingController();
  final subjectController=TextEditingController();
  final totalQuestionController=TextEditingController();

  final ExamService _examService=ExamService();
  bool isLoading=false;
  Future<void> createExam() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final result = await _examService.createExam(
        title: titleController.text.trim(),
        subject: subjectController.text.trim(),
        totalQuestions: int.parse(
          totalQuestionController.text.trim(),
        ),

      );
      debugPrint('CREATE EXAM RESPONSE: $result');

      if (!mounted) return;

      Navigator.pushReplacementNamed(
        context,
        AppRoutes.examDetails,
        arguments: result['exam'],
      );

      debugPrint(result.toString());

    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }
  @override
  void dispose() {
    titleController.dispose();
    subjectController.dispose();
    totalQuestionController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(

      appBar: AppBar(
        title: Text('Create Exam'),
      ),
      body: SafeArea(
          child: Padding(
          padding: const EdgeInsets.all(30),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Create a new exam",
                    style: AppTextStyles.heading,
                  ),
                  SizedBox(
                    height: 24,
                  ),

                  Text(
                    'Enter your information below.',
                    style: AppTextStyles.body,
                  ),
                  SizedBox(
                    height: 16,
                  ),
                  TextFormField(
                    controller: titleController,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                      labelText: "Exam title"
                    ),

                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: subjectController,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: "subject"
                    ),
                  ),
                  const SizedBox(height: 16,),

                  TextFormField(
                    controller: totalQuestionController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Total Questions",
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Total questions is required';
                      }

                      final total = int.tryParse(value);

                      if (total == null || total <= 0) {
                        return 'Enter a valid number';
                      }

                      return null;
                    },
                  ),
                  SizedBox(height: 24,),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(onPressed: isLoading? null : createExam,

                      child: isLoading
                      ? const CircularProgressIndicator()
                          : const Text("Create Exam"),
                    ),
                  )
                ],
              ),
            ),
      )
      ),
    );
  }
}
