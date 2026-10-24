import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Phone alerts (Android system notifications) while the app is running. On the web only the in-app list is used.
/// Alerts while the app is fully closed would need a push service (FCM / UnifiedPush); Supabase has none.
class Notifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _id = 0;

  Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('notifications unavailable: $e');
    }
  }

  Future<void> show(String title, String body) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _id++,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('mahjong_updates', 'Game & rule updates', importance: Importance.high, priority: Priority.high),
        ),
      );
    } catch (e) {
      debugPrint('notification failed: $e');
    }
  }
}
