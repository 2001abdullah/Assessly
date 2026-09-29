import 'dart:io';

import 'package:flutter/material.dart';

import '../services/grading_service.dart';
import '../utils/scan_errors.dart';
import '../widgets/app_widgets.dart';

enum BatchJobStatus { queued, reading, scoring, done, failed }

class BatchJob {
  BatchJob({
    required this.id,
    required this.examId,
    required this.examTitle,
    required this.image,
  }) : createdAt = DateTime.now();

  final String id;
  final String examId;
  final String examTitle;
  final File image;
  final DateTime createdAt;

  BatchJobStatus status = BatchJobStatus.queued;
  String? error;
  String? resultId;
  Map<String, dynamic>? result;

  /// Another sheet in this session was already graded with the same roll.
  bool duplicateRoll = false;

  bool get isActive =>
      status == BatchJobStatus.queued ||
      status == BatchJobStatus.reading ||
      status == BatchJobStatus.scoring;

  String get roll => formatIdentifier(result?['roll']);
}

/// App-wide background queue for batch scanning.
///
/// The camera drops each captured sheet in here and keeps scanning; sheets are
/// uploaded, read and scored one after another even if the user leaves the
/// scan screen. Every graded sheet is saved on the server, and [onResultSaved]
/// lets the results cache refresh.
class BatchScanProvider extends ChangeNotifier {
  BatchScanProvider({GradingService? grading, this.onResultSaved})
    : _grading = grading ?? GradingService();

  final GradingService _grading;
  final void Function(String examId)? onResultSaved;

  final List<BatchJob> _jobs = [];
  bool _running = false;
  int _nextId = 0;

  List<BatchJob> get jobs => List.unmodifiable(_jobs);

  List<BatchJob> jobsFor(String examId) =>
      _jobs.where((j) => j.examId == examId).toList();

  int get activeCount => _jobs.where((j) => j.isActive).length;
  int get doneCount =>
      _jobs.where((j) => j.status == BatchJobStatus.done).length;
  int get failedCount =>
      _jobs.where((j) => j.status == BatchJobStatus.failed).length;
  bool get isProcessing => activeCount > 0;

  void enqueue({required Map<String, dynamic> exam, required File image}) {
    _jobs.insert(
      0,
      BatchJob(
        id: 'job-${_nextId++}',
        examId: exam['id'].toString(),
        examTitle: exam['title']?.toString() ?? 'Exam',
        image: image,
      ),
    );
    notifyListeners();
    _pump();
  }

  void retry(BatchJob job) {
    if (job.status != BatchJobStatus.failed) return;
    job
      ..status = BatchJobStatus.queued
      ..error = null;
    notifyListeners();
    _pump();
  }

  void retryAllFailed(String examId) {
    for (final job in jobsFor(examId)) {
      if (job.status == BatchJobStatus.failed) {
        job
          ..status = BatchJobStatus.queued
          ..error = null;
      }
    }
    notifyListeners();
    _pump();
  }

  void remove(BatchJob job) {
    if (job.status == BatchJobStatus.reading ||
        job.status == BatchJobStatus.scoring) {
      return; // already uploading; let it finish
    }
    _jobs.remove(job);
    _deleteImage(job);
    notifyListeners();
  }

  /// Drops finished (saved) sheets for [examId] from the queue view. Their
  /// results stay saved on the server.
  void clearFinished(String examId) {
    _jobs.removeWhere(
      (j) => j.examId == examId && j.status == BatchJobStatus.done,
    );
    notifyListeners();
  }

  /// Processes queued sheets one at a time (oldest first).
  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      for (var job = _nextQueued(); job != null; job = _nextQueued()) {
        await _process(job);
      }
    } finally {
      _running = false;
    }
  }

  /// Jobs are stored newest first, so the oldest queued one is the last.
  BatchJob? _nextQueued() {
    for (var i = _jobs.length - 1; i >= 0; i--) {
      if (_jobs[i].status == BatchJobStatus.queued) return _jobs[i];
    }
    return null;
  }

  Future<void> _process(BatchJob job) async {
    try {
      final graded = await _grading.grade(
        examId: job.examId,
        image: job.image,
        onStage: (stage) {
          job.status = stage == GradeStage.reading
              ? BatchJobStatus.reading
              : BatchJobStatus.scoring;
          notifyListeners();
        },
      );
      // Signed out (reset) while this sheet was uploading: drop it.
      if (!_jobs.contains(job)) return;
      job
        ..status = BatchJobStatus.done
        ..resultId = graded.resultId
        ..result = graded.result;
      job.duplicateRoll =
          job.roll != '-' &&
          _jobs.any(
            (other) =>
                !identical(other, job) &&
                other.examId == job.examId &&
                other.status == BatchJobStatus.done &&
                other.roll == job.roll,
          );
      _deleteImage(job);
      onResultSaved?.call(job.examId);
    } catch (e) {
      job
        ..status = BatchJobStatus.failed
        ..error = friendlyScanError(e);
    }
    notifyListeners();
  }

  /// Captured photos live in the cache folder; failed ones are kept for retry.
  void _deleteImage(BatchJob job) {
    job.image.delete().catchError((_) => job.image);
  }

  void reset() {
    for (final job in _jobs) {
      _deleteImage(job);
    }
    _jobs.clear();
    notifyListeners();
  }
}
