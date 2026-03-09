import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';

/// Renders a single chat bubble — outgoing (right, green) or incoming
/// (left, white) — including image attachments, timestamps, and read receipts.
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  void _openImageViewer(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenImageViewer(imageUrl: imageUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageOnly = message.imageUrl != null && !message.hasContent;
    final hasImage = message.imageUrl != null;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
        isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: isMe ? const Color(0xFF2E7D32) : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMe ? 18 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            // Clip so the image respects the bubble's rounded corners.
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Image attachment
                if (hasImage)
                  GestureDetector(
                    onTap: () => _openImageViewer(context, message.imageUrl!),
                    child: CachedNetworkImage(
                      // Strip query params for a stable cache key.
                      cacheKey: Uri.parse(message.imageUrl!)
                          .replace(query: '')
                          .toString(),
                      imageUrl: message.imageUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        height: 180,
                        color: isMe
                            ? const Color(0xFF1B5E20)
                            : Colors.grey[200],
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: isMe ? Colors.white54 : Colors.grey,
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        height: 100,
                        color: isMe
                            ? const Color(0xFF1B5E20)
                            : Colors.grey[200],
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image,
                                  color: isMe
                                      ? Colors.white54
                                      : Colors.grey[400],
                                  size: 32),
                              const SizedBox(height: 4),
                              Text(
                                'Could not load image',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isMe
                                      ? Colors.white54
                                      : Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Text + timestamp (with padding) for messages that have text.
                // For image-only messages the timestamp is overlaid on the image.
                if (!imageOnly)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message.hasContent)
                          Text(
                            message.content!,
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.black87,
                              fontSize: 15,
                            ),
                          ),
                        if (message.hasContent) const SizedBox(height: 4),
                        _TimestampRow(message: message, isMe: isMe),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // For image-only bubbles, show timestamp below the bubble
          // (overlaying inside a Stack clips weirdly in Column layout).
          if (imageOnly)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
              child: _TimestampRow(message: message, isMe: isMe),
            ),
        ],
      ),
    );
  }
}

// Timestamp + read-receipt row

class _TimestampRow extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;

  const _TimestampRow({
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final timeColor =
    isMe ? Colors.white.withOpacity(0.65) : Colors.grey[400]!;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message.formattedTime,
          style: TextStyle(fontSize: 10, color: timeColor),
        ),
        if (isMe) ...[
          const SizedBox(width: 4),
          Icon(
            message.isOptimistic
                ? Icons.access_time_rounded  // sending
                : message.isRead
                ? Icons.done_all_rounded // read
                : Icons.done_rounded,    // delivered
            size: 13,
            color: message.isRead
                ? Colors.lightBlueAccent
                : Colors.white.withOpacity(0.65),
          ),
        ],
      ],
    );
  }
}

// Full-screen image viewer

class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;

  const _FullScreenImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: CachedNetworkImage(
            cacheKey: Uri.parse(imageUrl).replace(query: '').toString(),
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (_, __) => const CircularProgressIndicator(
              color: Colors.white,
            ),
            errorWidget: (_, __, ___) => const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, color: Colors.white54, size: 48),
                SizedBox(height: 12),
                Text('Could not load image',
                    style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}