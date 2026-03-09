import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/conversation_summary.dart';
import '../../../services/chat_service.dart';
import '../../../widgets/conversation_tile.dart';
import 'chat_room_page.dart';

/// Shows all conversations for the currently logged-in user.
/// Keeps itself up-to-date via a Supabase Realtime channel that triggers a
/// re-fetch whenever a message is inserted or updated in any of the user's
/// conversations.
class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final _service = ChatService.instance;

  List<ConversationSummary> _conversations = [];
  bool _isLoading = true;
  RealtimeChannel? _channel;

  String? get _uid => _service.currentUserId;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadConversations() async {
    final uid = _uid;
    if (uid == null) return;

    try {
      final summaries = await _service.fetchConversations(uid);
      if (mounted) {
        setState(() {
          _conversations = summaries;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ChatListPage: load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToMessages() {
    final uid = _uid;
    if (uid == null) return;

    _channel = _service
        .conversationListChannel(
      uid: uid,
      onInsert: (_) => _loadConversations(),
      onUpdate: (_) => _loadConversations(),
    )
        .subscribe();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> _openConversation(ConversationSummary summary) async {
    // Optimistically zero the badge the moment the user taps the row —
    // don't wait for the network round-trip, which can lose the race against
    // the re-fetch that fires when we return from the room.
    if (summary.unreadCount > 0) {
      setState(() {
        _conversations = _conversations.map((c) {
          return c.conversationId == summary.conversationId
              ? ConversationSummary(
            conversationId: c.conversationId,
            otherUserId: c.otherUserId,
            otherUserName: c.otherUserName,
            otherUserAvatar: c.otherUserAvatar,
            lastMessage: c.lastMessage,
            lastMessageTime: c.lastMessageTime,
            unreadCount: 0,
          )
              : c;
        }).toList();
      });
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomPage(
          conversationId: summary.conversationId,
          otherUserId: summary.otherUserId,
          otherUserName: summary.otherUserName,
          otherUserAvatar: summary.otherUserAvatar,
        ),
      ),
    );
    // Full re-fetch on return to sync any changes that happened while in the room.
    _loadConversations();
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Messages',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFEEEEEE)),
        ),
      ),
      body: _isLoading
          ? const Center(
          child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : _conversations.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
        color: const Color(0xFF2E7D32),
        onRefresh: _loadConversations,
        child: ListView.separated(
          itemCount: _conversations.length,
          separatorBuilder: (_, __) => const Divider(
            height: 1,
            indent: 80,
            color: Color(0xFFEEEEEE),
          ),
          itemBuilder: (context, index) => ConversationTile(
            summary: _conversations[index],
            onTap: () => _openConversation(_conversations[index]),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a conversation from a product page',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
        ],
      ),
    );
  }
}