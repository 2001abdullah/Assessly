import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/omr_service.dart';

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
  final ImagePicker _imagePicker = ImagePicker();

  File? selectedImage;

  Map<String, dynamic>? scanResult;
  Map<String, dynamic>? scoreResult;

  bool isScanning = false;
  bool isScoring = false;

  // --------------------------------------------------
  // PICK IMAGE
  // --------------------------------------------------

  Future<void> pickImage() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
      );

      if (file == null || file.path == null) return;

      setState(() {
        selectedImage = File(file.path!);
        scanResult = null;
        scoreResult = null;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
    }
  }

  Future<void> takePicture() async {
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
      );

      if (photo == null) return;

      setState(() {
        selectedImage = File(photo.path);
        scanResult = null;
        scoreResult = null;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to take picture: $e')));
    }
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
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
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
            // SELECT IMAGE
            // ------------------------------------------
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isScanning || isScoring ? null : takePicture,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Take Picture'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isScanning || isScoring ? null : pickImage,
                    icon: const Icon(Icons.image),
                    label: const Text('Choose Image'),
                  ),
                ),
              ],
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

  // ==================================================
  // OMR RESULT CARD
  // ==================================================

  Widget _buildScanResultCard() {
    final result = scanResult!;

    final roll = result['roll']?.toString() ?? '-';

    final registration = result['registration']?.toString() ?? '-';

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
