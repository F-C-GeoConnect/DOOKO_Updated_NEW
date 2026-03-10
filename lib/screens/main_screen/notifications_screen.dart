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

  void _initRealtimeNotifications() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    _fetchNotifications(userId);

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

  Future<void> _markAsRead(String id) async {
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
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) _fetchNotifications(userId);
    }
  }

  Future<void> _markAllAsRead() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final hasUnread = _notifications.any((n) => n['is_read'] == false);
    if (!hasUnread) return;

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
    setState(() {
      _notifications =
          _notifications.where((n) => n['id'].toString() != id).toList();
    });

    try {
      await _supabase.from('notifications').delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting notification: $e');
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
    final colorScheme = Theme.of(context).colorScheme;

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
          if (_notifications.isNotEmpty)
            TextButton.icon(
              onPressed: _markAllAsRead,
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Mark all read'),
              style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : _notifications.isEmpty
          ? _buildEmptyState(colorScheme)
          : ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _notifications.length,
        separatorBuilder: (context, index) => const Divider(height: 1, indent: 70),
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
              color: Colors.red.shade400,
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            onDismissed: (_) => _deleteNotification(id),
            child: ListTile(
              onTap: () {
                if (!isRead) _markAsRead(id);
                _handleNotificationTap(type, notification['related_id']);
              },
              tileColor: isRead ? Colors.transparent : colorScheme.primary.withOpacity(0.03),
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              leading: _getNotificationIcon(type, isRead, colorScheme),
              title: Text(
                notification['title'] ?? 'Notification',
                style: TextStyle(
                  fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                  fontSize: 15,
                  color: isRead ? Colors.black87 : Colors.black,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    notification['message'] ?? '',
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatTimestamp(notification['created_at']),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              trailing: !isRead
                  ? Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
              )
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.notifications_none_rounded, size: 80, color: colorScheme.primary.withOpacity(0.3)),
          ),
          const SizedBox(height: 24),
          const Text(
            'All caught up!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'No new notifications for you right now.',
            style: TextStyle(color: Colors.grey[600], fontSize: 15),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  Widget _getNotificationIcon(String type, bool isRead, ColorScheme colorScheme) {
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
        color = colorScheme.primary;
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
      child: Icon(iconData, color: color, size: 22),
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
    // Handle taps...
  }
}
