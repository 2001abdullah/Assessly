import 'package:flutter/material.dart';

import '../services/authed_http.dart';
import '../services/profile_service.dart';
import '../themes/app_colors.dart';

/// A user's profile picture, or their initials when there is none.
///
/// The picture needs the signed-in user's token, so the auth headers are
/// resolved first. [version] (the avatar's updated-at time) is part of the
/// image key, so a new picture replaces the cached one.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.userId,
    required this.name,
    required this.hasAvatar,
    this.version,
    this.size = 44,
    this.ring = false,
  });

  final String? userId;
  final String name;
  final bool hasAvatar;
  final String? version;
  final double size;

  /// White ring, for avatars on dark headers.
  final bool ring;

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Widget _fallback() => Container(
    color: AppColors.primarySoft,
    alignment: Alignment.center,
    child: Text(
      _initials,
      style: TextStyle(
        color: AppColors.primaryDark,
        fontWeight: FontWeight.w800,
        fontSize: size * 0.36,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (!hasAvatar || userId == null) {
      child = _fallback();
    } else {
      child = FutureBuilder<Map<String, String>>(
        future: AuthedHttp.authHeaders(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return _fallback();
          return Image.network(
            '${ProfileService.avatarUrl(userId!)}?v=${Uri.encodeComponent(version ?? '')}',
            key: ValueKey('avatar-$userId-$version'),
            headers: snapshot.data,
            fit: BoxFit.cover,
            width: size,
            height: size,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _fallback(),
          );
        },
      );
    }
    return Container(
      width: size,
      height: size,
      padding: ring ? EdgeInsets.all(size * 0.04) : null,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ring ? Colors.white : null,
      ),
      child: ClipOval(child: SizedBox.expand(child: child)),
    );
  }
}
