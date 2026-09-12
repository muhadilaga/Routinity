import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/activity.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    if (kIsWeb) return;
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings: settings);
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }

  Future<void> schedule(
    Activity activity, {
    bool immediateReminder = false,
  }) async {
    if (kIsWeb) return;
    final scheduledAt = immediateReminder
        ? activity.startAt
        : activity.startAt.subtract(
            Duration(minutes: activity.reminderMinutes),
          );
    if (!scheduledAt.isAfter(DateTime.now())) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'routinity_reminders',
        'Pengingat kegiatan',
        channelDescription: 'Alarm dan pengingat jadwal Routinity',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        playSound: true,
        enableVibration: true,
      ),
    );

    await _plugin.zonedSchedule(
      id: _notificationId(activity.id),
      title: activity.title,
      body:
          'Dimulai ${activity.reminderMinutes} menit lagi • ${activity.category}',
      // Convert the device-local wall clock to an absolute instant. Using
      // tz.local directly defaults to UTC unless an IANA location is set.
      scheduledDate: tz.TZDateTime.from(scheduledAt.toUtc(), tz.UTC),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: activity.id,
    );
  }

  Future<void> cancel(String activityId) async {
    if (kIsWeb) return;
    await _plugin.cancel(id: _notificationId(activityId));
  }

  int _notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
