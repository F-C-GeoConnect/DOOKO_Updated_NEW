import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/chat_service.dart';

class ChatProvider with ChangeNotifier {
  final _service = ChatService.instance;
  int _totalUnreadCount = 0;
  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSubscription;

  int get totalUnreadCount => _totalUnreadCount;

  ChatProvider() {
    _listenToAuth();
    _init();
  }

  void _listenToAuth() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.tokenRefreshed ||
          event == AuthChangeEvent.initialSession) {
        _init();
      } else if (event == AuthChangeEvent.signedOut) {
        _cleanup();
        _totalUnreadCount = 0;
        notifyListeners();
      }
    });
  }

  void _init() {
    final uid = _service.currentUserId;
    if (uid == null) return;

    _cleanup(); // Close existing subscription if any
    _loadUnreadCount();
    _subscribeToMessages(uid);
  }

  void _cleanup() {
    _channel?.unsubscribe();
    _channel = null;
  }

  Future<void> _loadUnreadCount() async {
    final uid = _service.currentUserId;
    if (uid == null) return;

    try {
      final summaries = await _service.fetchConversations(uid);
      // Change: Count the number of conversations with unread messages,
      // as requested (2 conversations in screenshot = badge 2).
      _totalUnreadCount = summaries.where((s) => s.unreadCount > 0).length;
      notifyListeners();
    } catch (e) {
      debugPrint('ChatProvider: load error: $e');
    }
  }

  void _subscribeToMessages(String uid) {
    // Using a unique channel name to avoid conflicts with other pages
    _channel = Supabase.instance.client
        .channel('chat_provider_unread:$uid')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        _loadUnreadCount();
      },
    )
        .subscribe();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _cleanup();
    super.dispose();
  }

  // Allow manual refresh if needed
  Future<void> refresh() => _loadUnreadCount();
}