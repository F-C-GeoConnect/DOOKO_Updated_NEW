import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/chat_message.dart';
import '../../../services/chat_service.dart';
import '../../../widgets/date_separator.dart';
import '../../../widgets/message_bubble.dart';
import '../../../widgets/user_avatar.dart';

/// Full-screen 1-on-1 chat room.
///
/// • Loads the initial message history via [ChatService.fetchMessages].
/// • Stays in sync via a Supabase Realtime channel ([ChatService.chatRoomChannel]).
/// • Sends text with optimistic UI and images via [ChatService.sendImageMessage].
/// • Automatically marks incoming messages as read.
class ChatRoomPage extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  final String otherUserAvatar;

  const ChatRoomPage({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserAvatar,
  });

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _service = ChatService.instance;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoadingInitial = true;
  bool _isSending = false;
  bool _isUploading = false;
  bool _hasText = false;

  RealtimeChannel? _channel;

  String? get _uid => _service.currentUserId;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onTextChanged);
    _loadInitialMessages();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  void _onTextChanged() {
    final has = _messageController.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadInitialMessages() async {
    try {
      final data = await _service.fetchMessages(widget.conversationId);
      if (mounted) {
        setState(() {
          _messages = data;
          _isLoadingInitial = false;
        });
        _scrollToBottom(jump: true);
        _markAllAsRead();
      }
    } catch (e) {
      debugPrint('ChatRoomPage: load error: $e');
      if (mounted) setState(() => _isLoadingInitial = false);
    }
  }

  // ── Realtime ──────────────────────────────────────────────────────────────

  void _subscribeToMessages() {
    _channel = _service
        .chatRoomChannel(
      conversationId: widget.conversationId,
      onInsert: (payload) {
        final newMsg = payload.newRecord;
        if (newMsg.isEmpty) return;

        final incomingId = newMsg['id'].toString();
        final alreadyExists =
        _messages.any((m) => m['id'].toString() == incomingId);

        if (!alreadyExists) {
          // If this message is addressed to us, mark it as read immediately
          // in local state before adding it — so it never flashes as unread.
          final isForMe = newMsg['receiver_id'] == _uid;
          final displayMsg =
          isForMe ? {...newMsg, 'is_read': true} : newMsg;

          setState(() => _messages = [..._messages, displayMsg]);
          _scrollToBottom();

          // Persist the read status to Supabase in the background.
          if (isForMe) {
            _service.markMessageAsRead(incomingId);
          }
        }
      },
      onUpdate: (payload) {
        final updated = payload.newRecord;
        if (updated.isEmpty) return;
        final updatedId = updated['id'].toString();
        // This fires when the receiver marks our sent message as read —
        // patching here turns the single tick into double blue ticks.
        setState(() {
          _messages = _messages.map((m) {
            return m['id'].toString() == updatedId ? updated : m;
          }).toList();
        });
      },
      onDelete: (payload) {
        final deletedId = payload.oldRecord['id']?.toString();
        if (deletedId == null) return;
        setState(() {
          _messages = _messages
              .where((m) => m['id'].toString() != deletedId)
              .toList();
        });
      },
    )
        .subscribe();
  }

  // ── Read receipts ─────────────────────────────────────────────────────────

  Future<void> _markAllAsRead() async {
    final uid = _uid;
    if (uid == null) return;

    // Patch local state immediately so the UI clears unread indicators
    // without waiting for a realtime UPDATE event — the sender's screen
    // would never receive that event due to RLS (only the receiver can UPDATE).
    setState(() {
      _messages = _messages.map((m) {
        if (m['receiver_id'] == uid && m['is_read'] == false) {
          return {...m, 'is_read': true};
        }
        return m;
      }).toList();
    });

    await _service.markAllAsRead(
      conversationId: widget.conversationId,
      receiverId: uid,
    );
  }

  // ── Sending ───────────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final uid = _uid;
    if (uid == null) return;

    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    _messageController.clear();
    setState(() => _isSending = true);

    // Optimistic insert so the message appears instantly.
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final tempMsg = {
      'id': tempId,
      'conversation_id': widget.conversationId,
      'sender_id': uid,
      'receiver_id': widget.otherUserId,
      'content': text,
      'image_url': null,
      'is_read': false,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      '_is_optimistic': true,
    };

    setState(() => _messages = [..._messages, tempMsg]);
    _scrollToBottom();

    try {
      final confirmed = await _service.sendTextMessage(
        conversationId: widget.conversationId,
        senderId: uid,
        receiverId: widget.otherUserId,
        content: text,
      );
      // Replace the temp entry with the confirmed server record.
      setState(() {
        _messages = _messages.map((m) {
          return m['id'].toString() == tempId ? confirmed : m;
        }).toList();
      });
    } catch (e) {
      // Remove the optimistic message and show an error.
      setState(() {
        _messages =
            _messages.where((m) => m['id'].toString() != tempId).toList();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendImage() async {
    final uid = _uid;
    if (uid == null) return;

    final XFile? picked =
    await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;

    setState(() => _isUploading = true);

    try {
      final confirmed = await _service.sendImageMessage(
        conversationId: widget.conversationId,
        senderId: uid,
        receiverId: widget.otherUserId,
        file: File(picked.path),
      );
      setState(() => _messages = [..._messages, confirmed]);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (msg.contains('bucket not found') ||
            msg.contains('Bucket not found')) {
          msg =
          'Storage Error: Create a "chat_images" bucket in Supabase Storage.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ── Scroll ────────────────────────────────────────────────────────────────

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(max);
      } else {
        // Only animate if the user is already near the bottom.
        final current = _scrollController.position.pixels;
        if ((max - current) <= 300) {
          _scrollController.animateTo(
            max,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _isDifferentDay(String? a, String? b) {
    if (a == null || b == null) return false;
    try {
      final da = DateTime.parse(a).toLocal();
      final db = DateTime.parse(b).toLocal();
      return da.year != db.year ||
          da.month != db.month ||
          da.day != db.day;
    } catch (_) {
      return false;
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) {
      return const Scaffold(
          body: Center(child: Text('Session expired. Please log in.')));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildMessageList(uid)),
          if (_isUploading)
            LinearProgressIndicator(
              color: const Color(0xFF2E7D32),
              backgroundColor: Colors.green.shade50,
            ),
          _buildInputArea(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.black),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: Color(0xFFEEEEEE)),
      ),
      title: Row(
        children: [
          UserAvatar(
            avatarUrl: widget.otherUserAvatar,
            name: widget.otherUserName,
            radius: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.otherUserName,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'tap to view profile',
                  style: TextStyle(color: Colors.grey[400], fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(String uid) {
    if (_isLoadingInitial) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF2E7D32)));
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.waving_hand_outlined,
                size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              'Say hello to ${widget.otherUserName}!',
              style: TextStyle(color: Colors.grey[500], fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final raw = _messages[index];
        final msg = ChatMessage(raw);
        final isMe = msg.senderId == uid;
        final showSeparator = index == 0 ||
            _isDifferentDay(
                _messages[index - 1]['created_at'], raw['created_at']);

        return Column(
          children: [
            if (showSeparator) DateSeparator(isoDate: msg.createdAt),
            MessageBubble(message: msg, isMe: isMe),
          ],
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.image_outlined, color: Colors.grey),
              onPressed: _isUploading ? null : _sendImage,
              tooltip: 'Send image',
            ),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: _messageController,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Message…',
                    hintStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _hasText
                  ? GestureDetector(
                key: const ValueKey('send'),
                onTap: _isSending ? null : _sendMessage,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _isSending
                        ? Colors.grey[300]
                        : const Color(0xFF2E7D32),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
                ),
              )
                  : const SizedBox(
                  key: ValueKey('empty'), width: 44, height: 44),
            ),
          ],
        ),
      ),
    );
  }
}