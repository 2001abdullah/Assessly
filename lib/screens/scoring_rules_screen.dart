import 'package:flutter/material.dart';
import 'package:assessly/themes/app_colors.dart';
import 'package:assessly/themes/app_text_styles.dart';
import 'package:assessly/services/scoring_rules_service.dart';

class ScoringRulesScreen extends StatefulWidget {
  final Map<String, dynamic> exam;

  const ScoringRulesScreen({
    super.key,
    required this.exam,
  });

  @override
  State<ScoringRulesScreen> createState() =>
      _ScoringRulesScreenState();
}

class _ScoringRulesScreenState
    extends State<ScoringRulesScreen> {
  final ScoringRulesService _scoringRulesService =
  ScoringRulesService();

  late TextEditingController marksCorrectController;
  late TextEditingController marksWrongController;
  late TextEditingController marksBlankController;
  late TextEditingController passPercentageController;

  String ambiguousAs = 'review';
  bool clampNegativeTotal = true;

  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();

    marksCorrectController =
        TextEditingController(text: '1');

    marksWrongController =
        TextEditingController(text: '-0.5');

    marksBlankController =
        TextEditingController(text: '0');

    passPercentageController =
        TextEditingController(text: '40');

    loadScoringRules();
  }

  Future<void> loadScoringRules() async {
    try {
      final examId = widget.exam['id'].toString();

      final rules =
      await _scoringRulesService.getScoringRules(
        examId: examId,
      );

      marksCorrectController.text =
          rules['marks_correct'].toString();

      marksWrongController.text =
          rules['marks_wrong'].toString();

      marksBlankController.text =
          rules['marks_blank'].toString();

      passPercentageController.text =
          rules['pass_percentage'].toString();

      ambiguousAs =
          rules['ambiguous_as'].toString();

      clampNegativeTotal =
          rules['clamp_negative_total'] == true;
    } catch (e) {
      // A new exam may not have scoring rules yet.
      // In that case, keep the default values.
      //
      // We only show an error for unexpected failures.
      if (!e.toString().contains(
        'Scoring rules not found',
      )) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not load scoring rules: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> saveScoringRules() async {
    final marksCorrect =
    double.tryParse(
      marksCorrectController.text.trim(),
    );

    final marksWrong =
    double.tryParse(
      marksWrongController.text.trim(),
    );

    final marksBlank =
    double.tryParse(
      marksBlankController.text.trim(),
    );

    final passPercentage =
    double.tryParse(
      passPercentageController.text.trim(),
    );

    // Basic number validation
    if (marksCorrect == null ||
        marksWrong == null ||
        marksBlank == null ||
        passPercentage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter valid numbers',
          ),
        ),
      );

      return;
    }

    // Correct marks cannot be negative
    if (marksCorrect < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Marks for correct answer cannot be negative',
          ),
        ),
      );

      return;
    }

    // Wrong marks must be zero or negative
    if (marksWrong > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Marks for wrong answer must be 0 or negative',
          ),
        ),
      );

      return;
    }

    // Blank marks must be zero
    if (marksBlank != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Marks for blank answer must be 0',
          ),
        ),
      );

      return;
    }

    // Pass percentage must be 0-100
    if (passPercentage < 0 ||
        passPercentage > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pass percentage must be between 0 and 100',
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

      await _scoringRulesService.saveScoringRules(
        examId: examId,
        marksCorrect: marksCorrect,
        marksWrong: marksWrong,
        marksBlank: marksBlank,
        passPercentage: passPercentage,
        ambiguousAs: ambiguousAs,
        clampNegativeTotal: clampNegativeTotal,
      );

      if (!mounted) return;

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString(),
          ),
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
  void dispose() {
    marksCorrectController.dispose();
    marksWrongController.dispose();
    marksBlankController.dispose();
    passPercentageController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scoring Rules'),
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(
          child: CircularProgressIndicator(),
        )
            : SingleChildScrollView(
          padding: const EdgeInsets.all(20),
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
                'Configure how this exam will be scored',
                style:
                AppTextStyles.bodySecondary,
              ),

              const SizedBox(height: 24),

              // Correct answer
              _buildNumberField(
                label: 'Marks for correct answer',
                controller:
                marksCorrectController,
                hint: 'Example: 1',
              ),

              const SizedBox(height: 16),

              // Wrong answer
              _buildNumberField(
                label: 'Marks for wrong answer',
                controller:
                marksWrongController,
                hint: 'Example: -0.5',
              ),

              const SizedBox(height: 16),

              // Blank answer
              _buildNumberField(
                label: 'Marks for blank answer',
                controller:
                marksBlankController,
                hint: '0',
                readOnly: true,
              ),

              const SizedBox(height: 16),

              // Pass percentage
              _buildNumberField(
                label: 'Pass percentage',
                controller:
                passPercentageController,
                hint: 'Example: 40',
              ),

              const SizedBox(height: 24),

              Text(
                'Ambiguous answer',
                style: AppTextStyles.body,
              ),

              const SizedBox(height: 8),

              Container(
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius:
                  BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.border,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: ambiguousAs,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'review',
                        child: Text(
                          'Review',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'wrong',
                        child: Text(
                          'Treat as wrong',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'blank',
                        child: Text(
                          'Treat as blank',
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;

                      setState(() {
                        ambiguousAs = value;
                      });
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Clamp negative total
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius:
                  BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.border,
                  ),
                ),
                child: SwitchListTile(
                  contentPadding:
                  const EdgeInsets.symmetric(
                    horizontal: 16,
                  ),
                  title: Text(
                    'Clamp negative total',
                    style:
                    AppTextStyles.body,
                  ),
                  subtitle: Text(
                    'Prevent the final score from going below 0',
                    style:
                    AppTextStyles.bodySecondary,
                  ),
                  value: clampNegativeTotal,
                  onChanged: (value) {
                    setState(() {
                      clampNegativeTotal =
                          value;
                    });
                  },
                ),
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : saveScoringRules,
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
                    'Save Scoring Rules',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumberField({
    required String label,
    required TextEditingController controller,
    required String hint,
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.body,
        ),

        const SizedBox(height: 8),

        TextField(
          controller: controller,
          readOnly: readOnly,
          keyboardType:
          const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius:
              BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.border,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius:
              BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.border,
              ),
            ),
          ),
        ),
      ],
    );
  }
}