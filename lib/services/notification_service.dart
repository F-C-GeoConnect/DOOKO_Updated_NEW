import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  final _fcm = FirebaseMessaging.instance;
  final _supabase = Supabase.instance.client;

  Future<void> initNotifications() async {
    // 1. Request Permission
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted notification permission');
      
      // 2. Get Token and save it
      await _updateToken();

      // 3. Listen for token refresh
      _fcm.onTokenRefresh.listen((newToken) {
        _saveTokenToDatabase(newToken);
      });
    } else {
      debugPrint('User declined or has not accepted notification permission');
    }
  }

  Future<void> _updateToken() async {
    try {
      String? token = await _fcm.getToken();
      if (token != null) {
        await _saveTokenToDatabase(token);
      }
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
    }
  }

  Future<void> _saveTokenToDatabase(String token) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase.from('profiles').update({
        'fcm_token': token,
      }).eq('id', userId);
      debugPrint('FCM Token saved to database');
    } catch (e) {
      debugPrint('Error saving FCM token to database: $e');
    }
  }
}
