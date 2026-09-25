import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../services/omr_service.dart';
import 'camera_scan_screen.dart';

import 'package:assessly/services/scoring_services.dart';
import 'package:assessly/routes/app_routes.dart';

class ScanOmrScreen extends StatefulWidget {
  final Map<String, dynamic> exam;

  const ScanOmrScreen({super.key, required this.exam});

  @override
  State<ScanOmrScreen> createState() => _ScanOmrScreenState();
}

class _ScanOmrScreenState extends State<ScanOmrScreen> {
  final OmrService _omrService = OmrService();
  final ScoringService _scoringService = ScoringService();

  File? selectedImage;

  Map<String, dynamic>? scanResult;
  Map<String, dynamic>? scoreResult;

  bool isScanning = false;
  bool isScoring = false;

  /// Friendly explanation shown (with a Retake button) when a scan fails.
  String? scanFailure;

  // --------------------------------------------------
  // PICK/CAPTURE IMAGE
  // --------------------------------------------------

  Future<void> _getImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickImage(source: source);

      if (file == null) return;

      setState(() {
        selectedImage = File(file.path);
        scanResult = null;
        scoreResult = null;
        scanFailure = null;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to acquire image: $e')));
    }
  }

  /// Opens the live scanner. A captured sheet is scanned immediately.
  Future<void> _openCamera() async {
    final File? shot = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => const CameraScanScreen(),
        fullscreenDialog: true,
      ),
    );
    if (shot == null || !mounted) return;

    setState(() {
      selectedImage = shot;
      scanResult = null;
      scoreResult = null;
      scanFailure = null;
    });
    await scanOmr();
  }

  /// Turns engine/network errors into advice the user can act on.
  String _friendlyError(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '');
    final m = raw.toLowerCase();
    if (m.contains('corner registration')) {
      return 'We could not see all four corner squares. Keep the whole sheet '
          'inside the frame and do not cover the corners.';
    }
    if (m.contains('cut off')) {
      return 'Part of the sheet is cut off at the edge of the photo. Step back '
          'a little so the whole sheet is visible.';
    }
    if (m.contains('timing marks')) {
      return 'We could not lock onto the black marks along the sheet edges. '
          'Flatten the sheet, use even light, and check that this is the sheet '
          'printed for this exam.\n\n($raw)';
    }
    if (m.contains('could not read image')) {
      return 'The photo could not be opened. Please take it again.';
    }
    if (error is SocketException || m.contains('too long')) {
      return 'Could not reach the server. Check your connection and try again.';
    }
    return raw;
  }

  // --------------------------------------------------
  // SCAN + SCORE
  // --------------------------------------------------

  Future<void> scanOmr() async {
    if (selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an OMR image first')),
      );
      return;
    }

    final String examId = widget.exam['id'].toString();

    try {
      // ----------------------------------------------
      // START
      // ----------------------------------------------

      setState(() {
        isScanning = true;
        isScoring = false;
        scanResult = null;
        scoreResult = null;
        scanFailure = null;
      });

      // ----------------------------------------------
      // STEP 1: OMR SCAN
      // ----------------------------------------------

      final result = await _omrService.scanOmr(
        image: selectedImage!,
        examId: examId,
      );

      debugPrint('================ OMR RESULT ================');

      debugPrint(result.toString());

      if (!mounted) return;

      setState(() {
        scanResult = result;
        isScanning = false;
      });

      final scanOk = result['ok'] == true;
      if (!scanOk) {
        final errors = result['errors'];
        final message = errors is List && errors.isNotEmpty
            ? errors.map((error) => error.toString()).join('; ')
            : 'The image could not be recognized as a valid OMR sheet.';
        throw Exception(message);
      }

      setState(() {
        isScoring = true;
      });

      // ----------------------------------------------
      // STEP 2: GET SCAN ID
      // ----------------------------------------------

      final String? scanId = result['result_id']?.toString();

      if (scanId == null || scanId.isEmpty) {
        throw Exception('OMR scan completed but no result_id was returned.');
      }

      debugPrint('SCORING SCAN: $scanId');

      // ----------------------------------------------
      // STEP 3: SCORE OMR
      // ----------------------------------------------

      final scoredResult = await _scoringService.scoreScan(
        examId: examId,
        scanId: scanId,
      );

      debugPrint('================ SCORE RESULT ================');

      debugPrint(scoredResult.toString());

      if (!mounted) return;

      setState(() {
        scoreResult = scoredResult;
        isScoring = false;
      });

      // ----------------------------------------------
      // STEP 4: GO TO RESULT SCREEN
      // ----------------------------------------------

      if (!mounted) return;

      Navigator.pushReplacementNamed(
        context,
        AppRoutes.result,
        arguments: {'exam': widget.exam, 'scoreResult': scoredResult},
      );
    } catch (e) {
      debugPrint('SCAN ERROR: $e');

      if (!mounted) return;

      setState(() {
        isScanning = false;
        isScoring = false;
        scanFailure = _friendlyError(e);
      });
    }
  }

  Future<void> _scanBatch() async {
    final selection = await FilePicker.pickFiles(
      type: FileType.image,
    );
    if (selection.isEmpty || !mounted) return;
    try {
      setState(() => isScanning = true);
      final result = await _omrService.scanBatch(
        images: selection.where((file) => file.path != null).map((file) => File(file.path!)).toList(),
        examId: widget.exam['id'].toString(),
      );
      if (!mounted) return;
      final results = result['results'] as List? ?? const [];
      final successful = results.where((item) => item is Map && item['ok'] == true).length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Processed $successful of ${results.length} sheets.')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => isScanning = false);
    }
  }

  // --------------------------------------------------
  // BUILD
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final String examTitle = widget.exam['title']?.toString() ?? 'Exam';

    return Scaffold(
      appBar: AppBar(title: const Text('Scan OMR')),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,

          children: [
            // ------------------------------------------
            // EXAM TITLE
            // ------------------------------------------

            Text(
              examTitle,

              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 20),

            // ------------------------------------------
            // SELECT/CAPTURE IMAGE BUTTONS
            // ------------------------------------------
            FilledButton.icon(
              onPressed: isScanning || isScoring ? null : _openCamera,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan with camera'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: isScanning || isScoring
                  ? null
                  : () => _getImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('Choose from gallery'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: isScanning || isScoring ? null : _scanBatch,
              icon: const Icon(Icons.library_add_check_outlined),
              label: const Text('Scan multiple sheets'),
            ),

            const SizedBox(height: 16),

            // ------------------------------------------
            // IMAGE PREVIEW
            // ------------------------------------------
            if (selectedImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),

                child: Image.file(selectedImage!, fit: BoxFit.contain),
              ),

            if (selectedImage != null) const SizedBox(height: 20),

            // ------------------------------------------
            // SCAN BUTTON
            // ------------------------------------------
            ElevatedButton.icon(
              onPressed: selectedImage == null || isScanning || isScoring
                  ? null
                  : scanOmr,

              icon: isScanning || isScoring
                  ? const SizedBox(
                      width: 18,
                      height: 18,

                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner),

              label: Text(
                isScanning
                    ? 'Scanning...'
                    : isScoring
                    ? 'Calculating Result...'
                    : 'Scan OMR',
              ),
            ),

            const SizedBox(height: 24),

            // ------------------------------------------
            // FAILURE + RETAKE
            // ------------------------------------------
            if (scanFailure != null) ...[
              _buildFailureCard(),
              const SizedBox(height: 24),
            ],

            // ------------------------------------------
            // RAW OMR RESULT
            // ------------------------------------------
            if (scanResult != null) ...[
              const Text(
                'OMR Scan Result',

                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 12),

              _buildScanResultCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFailureCard() {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "Couldn't read this sheet",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(scanFailure!),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: isScanning || isScoring ? null : _openCamera,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Retake with camera'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================================================
  // OMR RESULT CARD
  // ==================================================

  Widget _buildScanResultCard() {
    final result = scanResult!;

    final roll = _formatIdentifier(result['roll']);

    final registration = _formatIdentifier(result['registration']);

    final answers = result['answers'];

    return Card(
      elevation: 2,

      child: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            _resultRow('Roll', roll),

            _resultRow('Registration', registration),

            const SizedBox(height: 10),

            if (answers is List)
              Text(
                'Detected Answers: ${answers.length}',

                style: const TextStyle(fontWeight: FontWeight.w600),
              ),

            _resultMessages('Errors', result['errors'], Colors.red),

            _resultMessages(
              'Warnings',
              result['warnings'],
              Colors.orange.shade800,
            ),
          ],
        ),
      ),
    );
  }

  String _formatIdentifier(dynamic field) {
    if (field is Map) {
      final value = field['value']?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
      return '-';
    }

    final value = field?.toString().trim();
    return value == null || value.isEmpty ? '-' : value;
  }

  Widget _resultMessages(String label, dynamic messages, Color color) {
    if (messages is! List || messages.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        '$label: ${messages.map((message) => message.toString()).join('; ')}',
        style: TextStyle(color: color),
      ),
    );
  }

  // ==================================================
  // RESULT ROW
  // ==================================================

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),

      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,

        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),

          Flexible(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
