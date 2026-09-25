import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/results_service.dart';

class StudentResultsScreen extends StatefulWidget {
  final Map<String, dynamic> exam;

  const StudentResultsScreen({super.key, required this.exam});

  @override
  State<StudentResultsScreen> createState() => _StudentResultsScreenState();
}

class _StudentResultsScreenState extends State<StudentResultsScreen> {
  final ResultsService _service = ResultsService();
  late Future<List<Map<String, dynamic>>> _results;

  @override
  void initState() {
    super.initState();
    _results = _service.getExamResults(widget.exam['id'].toString());
  }

  Future<void> _export() async {
    try {
      final bytes = await _service.downloadCsv(widget.exam['id'].toString());
      final path = await FilePicker.saveFile(
        dialogTitle: 'Export student results',
        fileName: '${widget.exam['title']}-results.csv',
        bytes: bytes,
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $path')));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Results'),
        actions: [IconButton(onPressed: _export, icon: const Icon(Icons.download), tooltip: 'Export CSV')],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _results,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text(snapshot.error.toString()));
          final results = snapshot.data ?? const [];
          if (results.isEmpty) return const Center(child: Text('No student results yet.'));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: results.length,
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final result = results[index];
              return ListTile(
                tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                title: Text('Roll: ${result['roll_number'] ?? '-'}'),
                subtitle: Text('Registration: ${result['registration_number'] ?? '-'}'),
                trailing: Text('${result['percentage'] ?? 0}%\n${result['marks'] ?? 0} marks', textAlign: TextAlign.end),
              );
            },
          );
        },
      ),
    );
  }
}