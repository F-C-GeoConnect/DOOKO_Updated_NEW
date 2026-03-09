import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/conversation_summary.dart';

/// All Supabase data access for the chat feature lives here.
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  // ── Conversation helpers ──────────────────────────────────────────────────

  static String buildConversationId(String userA, String userB) {
    final ids = [userA, userB]..sort();
    return ids.join('_');
  }

  // ── Conversation list ─────────────────────────────────────────────────────

  Future<List<ConversationSummary>> fetchConversations(String uid) async {
    final data = await _supabase
        .from('messages')
        .select(
        'conversation_id, sender_id, receiver_id, content, image_url, is_read, created_at')
        .or('sender_id.eq.$uid,receiver_id.eq.$uid')
        .order('created_at', ascending: false, nullsFirst: false)
        .order('id', ascending: false);

    final messages = List<Map<String, dynamic>>.from(data);

    final Map<String, Map<String, dynamic>> latest = {};
    for (final m in messages) {
      final cid = m['conversation_id'] as String?;
      if (cid == null) continue;
      if (!latest.containsKey(cid)) {
        latest[cid] = m;
      }
    }

    final otherIds = latest.values.map((m) {
      return (m['sender_id'] as String) == uid
          ? m['receiver_id'] as String
          : m['sender_id'] as String;
    }).toSet();

    Map<String, Map<String, dynamic>> profiles = {};
    if (otherIds.isNotEmpty) {
      try {
        final profileData = await _supabase
            .from('profiles')
            .select('id, full_name, avatar_url')
            .inFilter('id', otherIds.toList());
        for (final p in List<Map<String, dynamic>>.from(profileData)) {
          profiles[p['id'] as String] = p;
        }
      } catch (e) {
        debugPrint('ChatService: profile fetch error: $e');
      }
    }

    final Map<String, int> unreadCounts = {};
    for (final m in messages) {
      final cid = m['conversation_id'] as String?;
      if (cid == null) continue;
      if (m['receiver_id'] == uid && m['is_read'] == false) {
        unreadCounts[cid] = (unreadCounts[cid] ?? 0) + 1;
      }
    }

    final summaries = latest.entries.map((e) {
      final cid = e.key;
      final m = e.value;
      final otherId = (m['sender_id'] as String) == uid
          ? m['receiver_id'] as String
          : m['sender_id'] as String;
      final profile = profiles[otherId];
      return ConversationSummary(
        conversationId: cid,
        otherUserId: otherId,
        otherUserName: profile?['full_name'] as String? ?? 'User',
        otherUserAvatar: profile?['avatar_url'] as String? ?? '',
        lastMessage:
        m['image_url'] != null ? '📷 Photo' : (m['content'] as String? ?? ''),
        lastMessageTime: m['created_at'] as String? ?? '',
        unreadCount: unreadCounts[cid] ?? 0,
      );
    }).toList();

    summaries.sort((a, b) {
      if (a.lastMessageTime.isEmpty && b.lastMessageTime.isEmpty) return 0;
      if (a.lastMessageTime.isEmpty) return 1;
      if (b.lastMessageTime.isEmpty) return -1;
      return b.lastMessageTime.compareTo(a.lastMessageTime);
    });
    return summaries;
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMessages(
      String conversationId) async {
    final data = await _supabase
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(200);
    
    final list = List<Map<String, dynamic>>.from(data);
    return list.reversed.toList();
  }

  Future<Map<String, dynamic>> sendTextMessage({
    required String conversationId,
    required String senderId,
    required String receiverId,
    required String content,
  }) async {
    final inserted = await _supabase
        .from('messages')
        .insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': content,
    })
        .select()
        .single();
    return inserted;
  }

  Future<Map<String, dynamic>> sendImageMessage({
    required String conversationId,
    required String senderId,
    required String receiverId,
    required File file,
  }) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_$senderId.jpg';
    final filePath = '$senderId/$fileName';

    // 1. Upload to bucket
    await _supabase.storage.from('chat_images').upload(filePath, file);
    
    // 2. ONLY store the path, not the public URL
    final imageUrl = filePath;

    final inserted = await _supabase
        .from('messages')
        .insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': null,
      'image_url': imageUrl,
    })
        .select()
        .single();
    return inserted;
  }

  // ── Read receipts ─────────────────────────────────────────────────────────

  Future<void> markAllAsRead({
    required String conversationId,
    required String receiverId,
  }) async {
    try {
      await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('conversation_id', conversationId)
          .eq('receiver_id', receiverId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('ChatService: markAllAsRead error: $e');
    }
  }

  Future<void> markMessageAsRead(String messageId) async {
    final id = int.tryParse(messageId);
    if (id == null) return;
    try {
      await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('id', id);
    } catch (e) {
      debugPrint('ChatService: markMessageAsRead error: $e');
    }
  }

  // ── Realtime channels ─────────────────────────────────────────────────────

  RealtimeChannel conversationListChannel({
    required String uid,
    required void Function(PostgresChangePayload) onInsert,
    required void Function(PostgresChangePayload) onUpdate,
  }) {
    return _supabase
        .channel('chat_list:$uid')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: onInsert,
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      callback: onUpdate,
    );
  }

  RealtimeChannel chatRoomChannel({
    required String conversationId,
    required void Function(PostgresChangePayload) onInsert,
    required void Function(PostgresChangePayload) onUpdate,
    required void Function(PostgresChangePayload) onDelete,
  }) {
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'conversation_id',
      value: conversationId,
    );

    return _supabase
        .channel('chat_room:$conversationId')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      filter: filter,
      callback: onInsert,
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      filter: filter,
      callback: onUpdate,
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'messages',
      filter: filter,
      callback: onDelete,
    );
  }
}
