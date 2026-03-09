/// Holds the data needed to render a single row in the conversation list.
class ConversationSummary {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  final String otherUserAvatar;
  final String lastMessage;
  final String lastMessageTime;
  final int unreadCount;

  const ConversationSummary({
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserAvatar,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.unreadCount,
  });
}