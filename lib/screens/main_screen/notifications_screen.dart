import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _initRealtimeNotifications();
  }

  /// Fetches an initial snapshot then subscribes to realtime INSERT / UPDATE /
  /// DELETE events — exactly mirroring the pattern used in home_page.dart so
  /// both screens always show a consistent view of the notifications table.
  void _initRealtimeNotifications() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    // 1. Populate the list immediately.
    _fetchNotifications(userId);

    // 2. Keep it in sync via realtime.
    _channel = _supabase
        .channel('notifications_screen:$userId')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord.isNotEmpty) {
          setState(() {
            _notifications = [newRecord, ..._notifications];
          });
        }
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (payload) {
        final updated = payload.newRecord;
        if (updated.isNotEmpty) {
          setState(() {
            _notifications = _notifications.map((n) {
              return n['id'] == updated['id'] ? updated : n;
            }).toList();
          });
        }
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (payload) {
        final deletedId = payload.oldRecord['id'];
        if (deletedId != null) {
          setState(() {
            _notifications =
                _notifications.where((n) => n['id'] != deletedId).toList();
          });
        }
      },
    )
        .subscribe();
  }

  Future<void> _fetchNotifications(String userId) async {
    try {
      final data = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Marks a single notification as read.
  /// The realtime UPDATE listener patches [_notifications] automatically,
  /// but we also apply an optimistic update for instant UI feedback.
  Future<void> _markAsRead(String id) async {
    // Optimistic update.
    setState(() {
      _notifications = _notifications.map((n) {
        return n['id'].toString() == id ? {...n, 'is_read': true} : n;
      }).toList();
    });

    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', id);
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
      // Re-fetch to roll back on failure.
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) _fetchNotifications(userId);
    }
  }

  Future<void> _markAllAsRead() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final hasUnread = _notifications.any((n) => n['is_read'] == false);
    if (!hasUnread) return;

    // Optimistic update.
    setState(() {
      _notifications = _notifications.map((n) {
        return n['is_read'] == false ? {...n, 'is_read': true} : n;
      }).toList();
    });

    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All notifications marked as read')),
        );
      }
    } catch (e) {
      debugPrint('Error marking all as read: $e');
      _fetchNotifications(userId);
    }
  }

  Future<void> _deleteNotification(String id) async {
    // Optimistic removal — the DELETE realtime event will also fire, which is
    // a no-op because the item is already gone from the list.
    setState(() {
      _notifications =
          _notifications.where((n) => n['id'].toString() != id).toList();
    });

    try {
      await _supabase.from('notifications').delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting notification: $e');
      // Re-fetch to restore the item on failure.
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) _fetchNotifications(userId);
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          TextButton(
            onPressed: _markAllAsRead,
            child:
            const Text('Mark all read', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : _notifications.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none,
                size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No notifications yet',
              style:
              TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      )
          : ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _notifications.length,
        separatorBuilder: (context, index) =>
        const Divider(height: 1),
        itemBuilder: (context, index) {
          final notification = _notifications[index];
          final bool isRead = notification['is_read'] ?? false;
          final String type = notification['type'] ?? 'general';
          final String id = notification['id'].toString();

          return Dismissible(
            key: Key(id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: Colors.red,
              child:
              const Icon(Icons.delete, color: Colors.white),
            ),
            // Optimistic removal happens inside _deleteNotification.
            onDismissed: (_) => _deleteNotification(id),
            child: ListTile(
              onTap: () {
                if (!isRead) _markAsRead(id);
                _handleNotificationTap(
                    type, notification['related_id']);
              },
              contentPadding: const EdgeInsets.symmetric(
                  vertical: 8, horizontal: 8),
              leading: _getNotificationIcon(type, isRead),
              title: Text(
                notification['title'] ?? 'Notification',
                style: TextStyle(
                  fontWeight: isRead
                      ? FontWeight.normal
                      : FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    notification['message'] ?? '',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTimestamp(notification['created_at']),
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[400]),
                  ),
                ],
              ),
              trailing: !isRead
                  ? Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle),
              )
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _getNotificationIcon(String type, bool isRead) {
    IconData iconData;
    Color color;

    switch (type) {
      case 'order':
        iconData = Icons.shopping_bag_outlined;
        color = Colors.blue;
        break;
      case 'delivery':
        iconData = Icons.local_shipping_outlined;
        color = Colors.orange;
        break;
      case 'selling':
        iconData = Icons.sell_outlined;
        color = Colors.green;
        break;
      case 'availability':
        iconData = Icons.check_circle_outline;
        color = Colors.purple;
        break;
      default:
        iconData = Icons.notifications_outlined;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, color: color, size: 24),
    );
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return '';
    final date = DateTime.parse(timestamp).toLocal();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) return '${difference.inDays}d ago';
    if (difference.inHours > 0) return '${difference.inHours}h ago';
    if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
    return 'Just now';
  }

  void _handleNotificationTap(String type, dynamic relatedId) {
    switch (type) {
      case 'order':
      // Navigator.push(context, MaterialPageRoute(builder: (context) => OrderDetails(id: relatedId)));
        break;
      case 'selling':
      // Navigator.push(context, MaterialPageRoute(builder: (context) => InventoryPage()));
        break;
      case 'availability':
      // Navigator.push(context, MaterialPageRoute(builder: (context) => ProductProfile(id: relatedId)));
        break;
      case 'delivery':
      // Navigator.push(context, MaterialPageRoute(builder: (context) => MapTracking(id: relatedId)));
        break;
    }
  }
}