import 'authed_http.dart';

/// Student-side API (`/api/student`): dashboard, classes, published results,
/// attendance and announcements. Only the signed-in student's own data.
class StudentService {
  const StudentService();

  Future<Map<String, dynamic>> overview() =>
      AuthedHttp.getJson('/api/student/overview');

  Future<List<Map<String, dynamic>>> classes() async =>
      listOf((await AuthedHttp.getJson('/api/student/classes'))['classes']);

  /// Sends a join request; the teacher must approve it.
  Future<String> joinClass(String code, String rollNumber) async =>
      (await AuthedHttp.postJson('/api/student/classes/join', {
        'code': code.trim(),
        'roll_number': rollNumber.trim(),
      }))['message'].toString();

  Future<void> leaveClass(String classId) =>
      AuthedHttp.deleteJson('/api/student/classes/$classId');

  Future<List<Map<String, dynamic>>> results() async =>
      listOf((await AuthedHttp.getJson('/api/student/results'))['results']);

  Future<Map<String, dynamic>> resultDetails(String resultId) async =>
      Map<String, dynamic>.from(
        (await AuthedHttp.getJson('/api/student/results/$resultId'))['result']
            as Map,
      );

  Future<List<Map<String, dynamic>>> attendance() async =>
      listOf((await AuthedHttp.getJson('/api/student/attendance'))['classes']);

  Future<List<Map<String, dynamic>>> announcements() async => listOf(
    (await AuthedHttp.getJson('/api/student/announcements'))['announcements'],
  );
}
