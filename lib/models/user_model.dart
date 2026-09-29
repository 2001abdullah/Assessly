/// Which side of the app an account uses.
enum UserRole {
  teacher,
  student;

  static UserRole parse(Object? value) =>
      value?.toString() == 'student' ? UserRole.student : UserRole.teacher;

  String get label => this == UserRole.student ? 'Student' : 'Teacher';
}

class UserModel {
  final String id;
  final String name;
  final String? email;

  /// Login name for student accounts a teacher created (no email).
  final String? username;
  final UserRole role;
  final String? phone;
  final String? institution;
  final String? bio;
  final bool hasAvatar;

  /// Changes whenever the picture changes; used to refresh cached images.
  final String? avatarUpdatedAt;

  /// Set on teacher-issued temporary passwords.
  final bool mustChangePassword;
  final bool hasPassword;
  final bool googleLinked;
  final String? createdAt;

  const UserModel({
    required this.id,
    required this.name,
    this.email,
    this.username,
    this.role = UserRole.teacher,
    this.phone,
    this.institution,
    this.bio,
    this.hasAvatar = false,
    this.avatarUpdatedAt,
    this.mustChangePassword = false,
    this.hasPassword = true,
    this.googleLinked = false,
    this.createdAt,
  });

  static String? _text(Object? v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'].toString(),
    name: (json['name'] ?? '').toString(),
    email: _text(json['email']),
    username: _text(json['username']),
    role: UserRole.parse(json['role']),
    phone: _text(json['phone']),
    institution: _text(json['institution']),
    bio: _text(json['bio']),
    hasAvatar: json['has_avatar'] == true,
    avatarUpdatedAt: _text(json['avatar_updated_at']),
    mustChangePassword: json['must_change_password'] == true,
    hasPassword: json['has_password'] != false,
    googleLinked: json['google_linked'] == true,
    createdAt: _text(json['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'username': username,
    'role': role.name,
    'phone': phone,
    'institution': institution,
    'bio': bio,
    'has_avatar': hasAvatar,
    'avatar_updated_at': avatarUpdatedAt,
    'must_change_password': mustChangePassword,
    'has_password': hasPassword,
    'google_linked': googleLinked,
    'created_at': createdAt,
  };

  bool get isStudent => role == UserRole.student;

  /// Email, or the username for teacher-created student logins.
  String get loginId => email ?? username ?? '';

  /// "Ada Lovelace" -> "AL"; used for the profile avatar.
  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get firstName {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.first;
  }
}
