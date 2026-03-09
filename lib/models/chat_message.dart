/// Wraps a raw Supabase message row with typed accessors and helpers.
///
/// NOTE: The messages table uses a `bigint` primary key (not UUID), so
/// Supabase returns `id` as a Dart [int]. All ID access goes through
/// [id] which normalises it to a [String] so comparisons with the
/// optimistic temp-ID strings are always safe.
class ChatMessage {
  final Map<String, dynamic> raw;

  const ChatMessage(this.raw);

  /// Always a [String] regardless of whether the underlying column is
  /// bigint (int) or uuid (String).
  String get id => raw['id'].toString();
  String get conversationId => raw['conversation_id'] as String? ?? '';
  String get senderId => raw['sender_id'] as String? ?? '';
  String get receiverId => raw['receiver_id'] as String? ?? '';
  String? get content => raw['content'] as String?;
  String? get imageUrl => raw['image_url'] as String?;
  bool get isRead => raw['is_read'] == true;
  String? get createdAt => raw['created_at'] as String?;

  /// True while the message has not yet been confirmed by Supabase.
  bool get isOptimistic => raw['_is_optimistic'] == true;

  bool get hasContent => content != null && content!.isNotEmpty;

  String get formattedTime {
    if (createdAt == null) return '--:--';
    try {
      final dt = DateTime.parse(createdAt!).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '--:--';
    }
  }
}