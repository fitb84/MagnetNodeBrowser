import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_client.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;

  // Initialize notifications
  static Future<void> initialize() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _notificationsPlugin.initialize(initSettings);
    _isInitialized = true;
  }

  // Show notification for active download
  static Future<void> showDownloadNotification({
    required String title,
    required String body,
    required int id,
    bool ongoing = true,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'downloads_channel',
      'Download Notifications',
      channelDescription: 'Notifications for active downloads',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      showProgress: true,
      maxProgress: 100,
      progress: 0,
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
    );
  }

  // Show download started notification
  static Future<void> showDownloadStarted(String name) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'download_started_channel',
      'Download Started',
      channelDescription: 'Notification when download starts',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      DateTime.now().millisecond,
      'Download Started',
      name.length > 50 ? '${name.substring(0, 47)}...' : name,
      notificationDetails,
    );
  }

  // Show download completed notification
  static Future<void> showDownloadCompleted(String name) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'download_completed_channel',
      'Download Completed',
      channelDescription: 'Notification when download completes',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      DateTime.now().millisecond,
      'Download Complete ✓',
      name.length > 50 ? '${name.substring(0, 47)}...' : name,
      notificationDetails,
    );
  }

  // Show batch submitted notification
  static Future<void> showBatchSubmitted(int count) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'batch_submitted_channel',
      'Batch Submitted',
      channelDescription: 'Notification when batch is submitted',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      999,
      'Batch Submitted',
      'Added $count magnet${count == 1 ? '' : 's'} to downloads',
      notificationDetails,
    );
  }

  // Cancel notification
  static Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  // Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }
}
