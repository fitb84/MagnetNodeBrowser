import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
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

    // Start background download monitoring
    await _initializeBackgroundTasks();
  }

  // Initialize background task for monitoring downloads
  static Future<void> _initializeBackgroundTasks() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    // Check downloads every 30 seconds
    await Workmanager().registerPeriodicTask(
      'downloadMonitor',
      'checkDownloads',
      frequency: const Duration(seconds: 30),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
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

// Top-level function for background task callback
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == 'checkDownloads') {
      try {
        final downloads = await ApiClient.getDownloads();

        // Check for active downloads (not seeding/stalled)
        final activeDownloads = downloads
            .where((dl) =>
                dl['state'] == 'downloading' ||
                (dl['progress'] as num? ?? 0) < 1.0)
            .toList();

        // Show summary notification if there are active downloads
        if (activeDownloads.isNotEmpty) {
          int totalSpeed = 0;
          for (var dl in activeDownloads) {
            final speedStr = dl['dlspeed'] as String? ?? '0 B/s';
            // Parse speed string
            if (speedStr.contains('MB/s')) {
              totalSpeed +=
                  (double.tryParse(speedStr.split(' ')[0]) ?? 0).toInt() * 1000;
            } else if (speedStr.contains('KB/s')) {
              totalSpeed += (double.tryParse(speedStr.split(' ')[0]) ?? 0).toInt();
            }
          }

          await NotificationService.showDownloadNotification(
            title: '📥 ${activeDownloads.length} Active',
            body: activeDownloads.length == 1
                ? activeDownloads[0]['name']
                    .toString()
                    .substring(0, 60)
                : '${activeDownloads.length} downloads active',
            id: 1001,
          );
        }

        return true;
      } catch (e) {
        return false;
      }
    }
    return false;
  });
}
