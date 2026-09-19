import 'dart:ui' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    const channel = AndroidNotificationChannel(
      'zone_events',
      'Zdarzenia stref',
      description: 'Alerty wejścia i wyjścia z geostref',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  static Future<void> show(int id, String title, String body) async {
    if (!_ready) await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'zone_events',
        'Zdarzenia stref',
        channelDescription: 'Alerty wejścia i wyjścia z geostref',
        importance: Importance.high,
        priority: Priority.high,
        color: Color(0xFF00897B),
      ),
    );
    await _plugin.show(id, title, body, details);
  }
}
