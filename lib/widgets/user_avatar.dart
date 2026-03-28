import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Displays a circular avatar with the user's photo, or a fallback initial
/// when [avatarUrl] is empty or fails to load.
class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final double radius;

  const UserAvatar({
    super.key,
    required this.avatarUrl,
    required this.name,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: avatarUrl!,
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: radius,
          backgroundImage: imageProvider,
        ),
        placeholder: (context, url) => CircleAvatar(
          radius: radius,
          backgroundColor: const Color(0xFFE8F5E9),
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
        errorWidget: (context, url, error) => _buildFallback(initial),
      );
    }

    return _buildFallback(initial);
  }

  Widget _buildFallback(String initial) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE8F5E9),
      child: Text(
        initial,
        style: TextStyle(
          color: const Color(0xFF2E7D32),
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
