import 'package:flutter/material.dart';
import 'package:assessly/themes/app_colors.dart';
import 'package:assessly/themes/app_text_styles.dart';
import 'package:assessly/services/answer_key_service.dart';

class AnswerKeyScreen extends StatefulWidget {
  final Map<String, dynamic> exam;

  const AnswerKeyScreen({
    super.key,
    required this.exam,
  });

  @override
  State<AnswerKeyScreen> createState() => _AnswerKeyScreenState();
}

class _AnswerKeyScreenState extends State<AnswerKeyScreen> {
  late List<String?> answers;

  final List<String> options = ['A', 'B', 'C', 'D'];

  final AnswerKeyService _answerKeyService = AnswerKeyService();

  bool isSaving = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();

    final totalQuestions = widget.exam['total_questions'] as int;

    answers = List<String?>.filled(
      totalQuestions,
      null,
    );

    loadAnswerKey();
  }

  Future<void> loadAnswerKey() async {
    try {
      final examId = widget.exam['id'].toString();

      final savedAnswers =
      await _answerKeyService.getAnswerKeys(
        examId: examId,
      );

      for (final answerKey in savedAnswers) {
        final questionNumber =
        answerKey['question_number'] as int;

        final correctAnswer =
        answerKey['correct_answer'].toString();

        final index = questionNumber - 1;

        if (index >= 0 && index < answers.length) {
          answers[index] = correctAnswer;
        }
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not load answer key: $e',
          ),
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

  Future<void> saveAnswerKey() async {
    final List<Map<String, dynamic>> configuredAnswers = [];

    for (int i = 0; i < answers.length; i++) {
      final answer = answers[i];

      if (answer != null) {
        configuredAnswers.add({
          'question_number': i + 1,
          'correct_answer': answer,
        });
      }
    }

    if (configuredAnswers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select at least one answer',
          ),
        ),
      );

      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final examId = widget.exam['id'].toString();

      await _answerKeyService.saveAnswerKey(
        examId: examId,
        answers: configuredAnswers,
      );

      if (!mounted) return;

      // Saving was successful.
      // Return to the previous screen.
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      // Saving failed, so stay on this screen
      // and show the error.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Answer Key'),
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(
          child: CircularProgressIndicator(),
        )
            : Column(
          children: [
            // Exam information
            Padding(
              padding: const EdgeInsets.fromLTRB(
                20,
                20,
                20,
                12,
              ),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.exam['title'],
                    style: AppTextStyles.title,
                  ),

                  const SizedBox(height: 4),

                  Text(
                    '${widget.exam['total_questions']} Questions',
                    style:
                    AppTextStyles.bodySecondary,
                  ),
                ],
              ),
            ),

            // Questions
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                ),
                itemCount: answers.length,
                itemBuilder: (context, index) {
                  final questionNumber = index + 1;

                  return Container(
                    margin: const EdgeInsets.only(
                      bottom: 12,
                    ),
                    padding:
                    const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius:
                      BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Question $questionNumber',
                          style:
                          AppTextStyles.body,
                        ),

                        const SizedBox(height: 12),

                        Wrap(
                          spacing: 8,
                          children:
                          options.map((option) {
                            return ChoiceChip(
                              label: Text(option),

                              selected:
                              answers[index] ==
                                  option,

                              onSelected: (_) {
                                setState(() {
                                  answers[index] =
                                      option;
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Save button
            Padding(
              padding:
              const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : saveAnswerKey,
                  child: isSaving
                      ? const SizedBox(
                    width: 24,
                    height: 24,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Text(
                    'Save Answer Key',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}