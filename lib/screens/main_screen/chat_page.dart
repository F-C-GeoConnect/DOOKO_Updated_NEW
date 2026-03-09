import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/chat_service.dart';
import 'chat/chat_list_page.dart';
import 'chat/chat_room_page.dart';

/// Entry point for the entire chat feature.
///
/// The rest of the app only ever imports THIS file — nothing else inside
/// `chat/` needs to be exposed to the outside world.
///
/// Usage from product_profile.dart or main.dart:
/// ```dart
/// Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (_) => ChatPage(
///       farmerName: 'Ram Bahadur',
///       receiverId: 'uuid-of-farmer',
///     ),
///   ),
/// );
/// ```
class ChatPage extends StatelessWidget {
  /// Display name of the other user (used as the chat room title).
  final String? farmerName;

  /// Supabase UUID of the other user.
  final String? receiverId;

  const ChatPage({super.key, this.farmerName, this.receiverId});

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in')),
      );
    }

    // Deep-link directly into a conversation when both params are supplied.
    if (receiverId != null && farmerName != null) {
      return ChatRoomPage(
        conversationId: ChatService.buildConversationId(
          currentUser.id,
          receiverId!,
        ),
        otherUserId: receiverId!,
        otherUserName: farmerName!,
        otherUserAvatar: '',
      );
    }

    // Default: show the full conversation list.
    return const ChatListPage();
  }
}