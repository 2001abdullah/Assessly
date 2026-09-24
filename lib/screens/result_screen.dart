import 'package:flutter/material.dart';

class ResultScreen extends StatelessWidget {
  final Map<String, dynamic> exam;
  final Map<String, dynamic> scoreResult;

  const ResultScreen({
    super.key,
    required this.exam,
    required this.scoreResult,
  });

  double _toDouble(dynamic value) {
    if (value == null) return 0;

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }

  String _formatIdentifier(dynamic field) {
    if (field is Map) {
      final value = field['value']?.toString().trim();
      if (value != null && value.isNotEmpty) return value;

      final digits = field['digits'];
      if (digits is List && digits.any((digit) => digit != null)) {
        return digits.map((digit) => digit?.toString() ?? '?').join();
      }

      return '-';
    }

    final value = field?.toString().trim();
    return value == null || value.isEmpty ? '-' : value;
  }

  @override
  Widget build(BuildContext context) {
    final result = scoreResult['result'];

    if (result == null || result is! Map) {
      return Scaffold(
        appBar: AppBar(title: const Text('Exam Result')),
        body: const Center(child: Text('No result data available.')),
      );
    }

    final String examTitle = exam['title']?.toString() ?? 'Exam';

    final String roll = _formatIdentifier(result['roll']);

    final String registration = _formatIdentifier(result['registration']);

    final int correct = result['correct'] ?? 0;

    final int wrong = result['wrong'] ?? 0;

    final int blank = result['blank'] ?? 0;

    final int ambiguous = result['ambiguous'] ?? 0;

    final double marks = _toDouble(result['marks']);

    final double maxMarks = _toDouble(result['max_marks']);

    final double percentage = _toDouble(result['percentage']);

    final String grade = result['grade']?.toString() ?? '-';

    final bool passed = result['passed'] == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Exam Result')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ==========================================
            // EXAM TITLE
            // ==========================================

            Text(
              examTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 24),

            // ==========================================
            // MAIN RESULT
            // ==========================================
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      passed ? Icons.check_circle : Icons.cancel,
                      size: 72,
                      color: passed ? Colors.green : Colors.red,
                    ),

                    const SizedBox(height: 12),

                    Text(
                      passed ? 'PASSED' : 'FAILED',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: passed ? Colors.green : Colors.red,
                      ),
                    ),

                    const SizedBox(height: 20),

                    Text(
                      '${marks.toStringAsFixed(2)} / ${maxMarks.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      '${percentage.toStringAsFixed(2)}%',
                      style: const TextStyle(fontSize: 22),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'Grade: $grade',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ==========================================
            // STUDENT INFORMATION
            // ==========================================
            const Text(
              'Student Information',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _infoRow('Roll', roll),

                    _infoRow('Registration', registration),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ==========================================
            // ANSWER STATISTICS
            // ==========================================
            const Text(
              'Answer Statistics',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: _statCard('Correct', correct.toString(), Icons.check),
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: _statCard('Wrong', wrong.toString(), Icons.close),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: _statCard('Blank', blank.toString(), Icons.remove),
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: _statCard(
                    'Ambiguous',
                    ambiguous.toString(),
                    Icons.help_outline,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

            // ==========================================
            // BACK
            // ==========================================
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Back to Scan'),
            ),
          ],
        ),
      ),
    );
  }

  // ================================================
  // INFO ROW
  // ================================================

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),

          Flexible(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  // ================================================
  // STAT CARD
  // ================================================

  Widget _statCard(String label, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, size: 28),

            const SizedBox(height: 8),

            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 4),

            Text(label),
          ],
        ),
      ),
    );
  }
}
