import 'package:flutter/material.dart';
import '../models/conversation_summary.dart';
import 'user_avatar.dart';

/// A single row in the conversation list showing the other user's avatar,
/// name, last message preview, relative time, and an unread badge.
class ConversationTile extends StatelessWidget {
  final ConversationSummary summary;
  final VoidCallback onTap;

  const ConversationTile({
    super.key,
    required this.summary,
    required this.onTap,
  });

  String _formatTime(String isoTime) {
    if (isoTime.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoTime).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays >= 1) return '${diff.inDays}d';
      if (diff.inHours >= 1) return '${diff.inHours}h';
      if (diff.inMinutes >= 1) return '${diff.inMinutes}m';
      return 'now';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = summary.unreadCount > 0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            UserAvatar(
              avatarUrl: summary.otherUserAvatar,
              name: summary.otherUserName,
              radius: 26,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Name + time ───────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          summary.otherUserName,
                          style: TextStyle(
                            fontWeight:
                            hasUnread ? FontWeight.bold : FontWeight.w600,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatTime(summary.lastMessageTime),
                        style: TextStyle(
                          fontSize: 12,
                          color: hasUnread
                              ? const Color(0xFF2E7D32)
                              : Colors.grey[400],
                          fontWeight: hasUnread
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // ── Last message + unread badge ───────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          summary.lastMessage,
                          style: TextStyle(
                            fontSize: 13,
                            color: hasUnread
                                ? Colors.black87
                                : Colors.grey[500],
                            fontWeight: hasUnread
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            summary.unreadCount > 99
                                ? '99+'
                                : summary.unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}