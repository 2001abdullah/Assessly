import 'dart:io';

import 'omr_service.dart';
import 'scoring_service.dart';

enum GradeStage { reading, scoring }

/// Outcome of grading one sheet. The result is already saved on the server.
class GradedSheet {
  const GradedSheet({required this.resultId, required this.result});

  final String resultId;

  /// Summary: roll, registration, correct, wrong, blank, ambiguous, marks,
  /// max_marks, percentage, grade, passed.
  final Map<String, dynamic> result;
}

/// Reads one OMR photo and scores it: the pipeline shared by single scans and
/// the background batch queue.
class GradingService {
  GradingService({OmrService? omr, ScoringService? scoring})
    : _omr = omr ?? OmrService(),
      _scoring = scoring ?? ScoringService();

  final OmrService _omr;
  final ScoringService _scoring;

  Future<GradedSheet> grade({
    required String examId,
    required File image,
    void Function(GradeStage stage)? onStage,
  }) async {
    onStage?.call(GradeStage.reading);
    final scan = await _omr.scanOmr(image: image, examId: examId);

    if (scan['ok'] != true) {
      final errors = scan['errors'];
      throw Exception(
        errors is List && errors.isNotEmpty
            ? errors.map((e) => e.toString()).join('; ')
            : 'The image could not be recognized as a valid OMR sheet.',
      );
    }

    final scanId = scan['result_id']?.toString();
    if (scanId == null || scanId.isEmpty) {
      throw Exception('OMR scan completed but no result_id was returned.');
    }

    onStage?.call(GradeStage.scoring);
    final scored = await _scoring.scoreScan(examId: examId, scanId: scanId);

    final resultId = scored['result_id']?.toString();
    if (resultId == null || resultId.isEmpty) {
      throw Exception('The sheet was scored but no result id was returned.');
    }

    final result = scored['result'];
    return GradedSheet(
      resultId: resultId,
      result: result is Map ? Map<String, dynamic>.from(result) : const {},
    );
  }
}
