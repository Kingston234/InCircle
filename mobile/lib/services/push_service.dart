import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import 'notification_service.dart';

class PushService {
  static bool _fbReady = false;
  static String? _token;

  static Future<bool> init() async {
    try {
      if (!_fbReady) {
        await Firebase.initializeApp();
        final fm = FirebaseMessaging.instance;
        await fm.requestPermission();
        _token = await fm.getToken();
        fm.onTokenRefresh.listen((t) {
          _token = t;
          _registerQuietly(t);
        });
        FirebaseMessaging.onMessage.listen((msg) {
          final n = msg.notification;
          if (n != null) {
            NotificationService.show(
                msg.hashCode, n.title ?? 'InCircle', n.body ?? '');
          }
        });
        _fbReady = true;
      }
      if (_token == null) return false;
      await ApiClient.instance.registerPushToken(_token!, 'android');
      debugPrint('Powiadomienia dostarcza Firebase');
      return true;
    } catch (e) {
      debugPrint('Ppowiadomienia lokalne: $e');
      return false;
    }
  }

  static Future<void> _registerQuietly(String token) async {
    try {
      await ApiClient.instance.registerPushToken(token, 'android');
    } catch (_) {
    }
  }
}
