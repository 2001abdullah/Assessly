import 'authed_http.dart';

/// Teacher-side class management (`/api/classes`): classes, roster, join
/// requests, attendance, announcements, analytics and reports.
class ClassService {
  const ClassService();

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Local calendar date as the server expects it (YYYY-MM-DD).
  static String dateKey(DateTime d) => _date(d);

  // ---------------------------------------------------------------- classes

  Future<List<Map<String, dynamic>>> list() async =>
      listOf((await AuthedHttp.getJson('/api/classes'))['classes']);

  Future<Map<String, dynamic>> dashboard() => AuthedHttp.getJson(
    '/api/classes/dashboard?date=${_date(DateTime.now())}',
  );

  Future<Map<String, dynamic>> create({
    required String name,
    String? subject,
    String? section,
    String? description,
  }) async {
    final data = await AuthedHttp.postJson('/api/classes', {
      'name': name,
      'subject': subject,
      'section': section,
      'description': description,
    });
    return Map<String, dynamic>.from(data['class'] as Map);
  }

  Future<Map<String, dynamic>> get(String classId) async =>
      Map<String, dynamic>.from(
        (await AuthedHttp.getJson('/api/classes/$classId'))['class'] as Map,
      );

  Future<Map<String, dynamic>> update(
    String classId, {
    required String name,
    String? subject,
    String? section,
    String? description,
  }) async {
    final data = await AuthedHttp.putJson('/api/classes/$classId', {
      'name': name,
      'subject': subject,
      'section': section,
      'description': description,
    });
    return Map<String, dynamic>.from(data['class'] as Map);
  }

  Future<void> delete(String classId) =>
      AuthedHttp.deleteJson('/api/classes/$classId');

  Future<String> newJoinCode(String classId) async =>
      (await AuthedHttp.postJson(
        '/api/classes/$classId/join-code',
      ))['join_code'].toString();

  // ---------------------------------------------------------------- roster

  Future<List<Map<String, dynamic>>> students(String classId) async => listOf(
    (await AuthedHttp.getJson('/api/classes/$classId/students'))['students'],
  );

  /// Returns `{student, credentials?}`; credentials (username + temporary
  /// password) only when [createLogin] is true, and only this once.
  Future<Map<String, dynamic>> addStudent(
    String classId, {
    required String name,
    required String rollNumber,
    String? email,
    bool createLogin = false,
  }) => AuthedHttp.postJson('/api/classes/$classId/students', {
    'name': name,
    'roll_number': rollNumber,
    'email': email,
    'create_login': createLogin,
  });

  Future<void> approve(String classId, String studentId) =>
      AuthedHttp.patchJson('/api/classes/$classId/students/$studentId', {
        'status': 'active',
      });

  Future<void> editStudent(
    String classId,
    String studentId, {
    String? name,
    String? rollNumber,
  }) => AuthedHttp.patchJson('/api/classes/$classId/students/$studentId', {
    'name': ?name,
    'roll_number': ?rollNumber,
  });

  Future<void> removeStudent(String classId, String studentId) =>
      AuthedHttp.deleteJson('/api/classes/$classId/students/$studentId');

  Future<Map<String, dynamic>> resetPassword(
    String classId,
    String studentId,
  ) async => Map<String, dynamic>.from(
    (await AuthedHttp.postJson(
          '/api/classes/$classId/students/$studentId/reset-password',
        ))['credentials']
        as Map,
  );

  Future<Map<String, dynamic>> studentReport(
    String classId,
    String studentId,
  ) => AuthedHttp.getJson('/api/classes/$classId/students/$studentId/report');

  // ---------------------------------------------------------------- exams

  Future<List<Map<String, dynamic>>> exams(String classId) async => listOf(
    (await AuthedHttp.getJson('/api/classes/$classId/exams'))['exams'],
  );

  // ---------------------------------------------------------------- attendance

  Future<List<Map<String, dynamic>>> attendanceSessions(String classId) async =>
      listOf(
        (await AuthedHttp.getJson(
          '/api/classes/$classId/attendance',
        ))['sessions'],
      );

  /// `{date, taken, note, records: [{student_id, name, roll_number, status?}]}`
  Future<Map<String, dynamic>> attendanceFor(String classId, DateTime day) =>
      AuthedHttp.getJson('/api/classes/$classId/attendance/${_date(day)}');

  Future<void> saveAttendance(
    String classId,
    DateTime day,
    Map<String, String> statusByStudent, {
    String? note,
  }) => AuthedHttp.putJson('/api/classes/$classId/attendance/${_date(day)}', {
    'note': note,
    'records': [
      for (final e in statusByStudent.entries)
        {'student_id': e.key, 'status': e.value},
    ],
  });

  // ---------------------------------------------------------------- announcements

  Future<List<Map<String, dynamic>>> announcements(String classId) async =>
      listOf(
        (await AuthedHttp.getJson(
          '/api/classes/$classId/announcements',
        ))['announcements'],
      );

  Future<void> postAnnouncement(String classId, String title, String body) =>
      AuthedHttp.postJson('/api/classes/$classId/announcements', {
        'title': title,
        'body': body,
      });

  Future<void> deleteAnnouncement(String classId, String id) =>
      AuthedHttp.deleteJson('/api/classes/$classId/announcements/$id');

  // ---------------------------------------------------------------- analytics

  Future<Map<String, dynamic>> analytics(String classId) =>
      AuthedHttp.getJson('/api/classes/$classId/analytics');

  Future<List<int>> resultsCsv(String classId) =>
      AuthedHttp.getBytes('/api/classes/$classId/reports/results.csv');

  Future<List<int>> attendanceCsv(String classId) =>
      AuthedHttp.getBytes('/api/classes/$classId/reports/attendance.csv');
}
