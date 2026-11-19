import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _updatesTopic = 'flixora_all_updates';
const String _notificationsPreferenceKey = 'flixora_notifications';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _updatesChannel = AndroidNotificationChannel(
  'flixora_updates',
  'FLIXORA Updates',
  description: 'New movies, series, dramas, anime and app updates.',
  importance: Importance.high,
);

const AndroidNotificationChannel _downloadsChannel = AndroidNotificationChannel(
  'flixora_downloads',
  'FLIXORA Downloads',
  description: 'Notifications when video downloads finish.',
  importance: Importance.high,
);

@pragma('vm:entry-point')
Future<void> flixoraFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  await Firebase.initializeApp();
  if (message.notification != null) return;

  final title = message.data['title']?.toString();
  final body = message.data['body']?.toString();
  if (title == null || title.isEmpty || body == null || body.isEmpty) return;

  const initializationSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await _localNotifications.initialize(initializationSettings);
  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_updatesChannel);
  await _localNotifications.show(
    message.messageId?.hashCode ?? message.hashCode,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'flixora_updates',
        'FLIXORA Updates',
        channelDescription:
            'New movies, series, dramas, anime and app updates.',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
  );
}

class FlixoraNotificationService {
  FlixoraNotificationService._();

  static bool _initialized = false;
  static bool _enabled = true;

  static Future<void> initialize() async {
    if (_initialized) return;

    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(
      flixoraFirebaseMessagingBackgroundHandler,
    );

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotifications.initialize(initializationSettings);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_updatesChannel);
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_downloadsChannel);

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_notificationsPreferenceKey) ?? true;
    _initialized = true;

    if (_enabled) {
      await _requestPermissionAndSubscribe();
    }
  }

  static Future<void> _showForegroundNotification(
    RemoteMessage message,
  ) async {
    if (!_enabled) return;
    final title = message.notification?.title ??
        message.data['title']?.toString();
    final body = message.notification?.body ??
        message.data['body']?.toString();
    if (title == null || title.isEmpty || body == null || body.isEmpty) return;

    await _localNotifications.show(
      message.messageId?.hashCode ?? message.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'flixora_updates',
          'FLIXORA Updates',
          channelDescription:
              'New movies, series, dramas, anime and app updates.',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  static Future<void> showDownloadComplete({
    required String title,
    required int uniqueId,
  }) async {
    try {
      if (!_initialized) await initialize();
      if (!_enabled) return;

      final videoTitle = title.trim();
      if (videoTitle.isEmpty) return;

      await _localNotifications.show(
        0x40000000 | (uniqueId & 0x3fffffff),
        'Download Complete',
        '$videoTitle has been downloaded successfully.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'flixora_downloads',
            'FLIXORA Downloads',
            channelDescription: 'Notifications when video downloads finish.',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (error) {
      debugPrint('Could not show FLIXORA download notification: $error');
    }
  }

  static Future<bool> _requestPermissionAndSubscribe() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final authorized =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!authorized) return false;

    await FirebaseMessaging.instance.subscribeToTopic(_updatesTopic);
    return true;
  }

  static Future<bool> enable() async {
    try {
      if (!_initialized) await initialize();
      final allowed = await _requestPermissionAndSubscribe();
      _enabled = allowed;
      return allowed;
    } catch (error) {
      debugPrint('Could not enable FLIXORA push notifications: $error');
      _enabled = false;
      return false;
    }
  }

  static Future<void> disable() async {
    _enabled = false;
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(_updatesTopic);
    } catch (error) {
      debugPrint('Could not unsubscribe FLIXORA notifications: $error');
    }
  }
}
