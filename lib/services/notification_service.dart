import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/activity.dart';

class NotificationPermissionStatus {
  const NotificationPermissionStatus({
    required this.notificationsEnabled,
    required this.exactAlarmsEnabled,
    required this.pendingCount,
  });

  final bool notificationsEnabled;
  final bool exactAlarmsEnabled;
  final int pendingCount;
}

class NotificationScheduleResult {
  const NotificationScheduleResult({
    required this.scheduled,
    this.usedExactAlarm = false,
    this.message,
  });

  final bool scheduled;
  final bool usedExactAlarm;
  final String? message;
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channel = AndroidNotificationDetails(
    'routinity_reminders_v2',
    'Pengingat kegiatan',
    channelDescription: 'Alarm dan pengingat jadwal Routinity',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.alarm,
    playSound: true,
    enableVibration: true,
  );

  Future<void> initialize() async {
    if (kIsWeb || _initialized) return;
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  Future<NotificationPermissionStatus> getStatus() async {
    if (kIsWeb) {
      return const NotificationPermissionStatus(
        notificationsEnabled: false,
        exactAlarmsEnabled: false,
        pendingCount: 0,
      );
    }
    await initialize();
    final android = _androidPlugin;
    final notificationsEnabled =
        await android?.areNotificationsEnabled() ?? true;
    final exactAlarmsEnabled =
        await android?.canScheduleExactNotifications() ?? true;
    final pending = await _plugin.pendingNotificationRequests();
    return NotificationPermissionStatus(
      notificationsEnabled: notificationsEnabled,
      exactAlarmsEnabled: exactAlarmsEnabled,
      pendingCount: pending.length,
    );
  }

  Future<NotificationPermissionStatus> requestPermissions() async {
    if (kIsWeb) return getStatus();
    await initialize();
    await _androidPlugin?.requestNotificationsPermission();
    if (!(await _androidPlugin?.canScheduleExactNotifications() ?? true)) {
      await _androidPlugin?.requestExactAlarmsPermission();
    }
    return getStatus();
  }

  Future<bool> openNotificationSettings() async {
    if (kIsWeb) return false;
    await initialize();
    return await _androidPlugin?.openAppNotificationSettings() ?? false;
  }

  Future<void> showTestNotification() async {
    if (kIsWeb) return;
    await initialize();
    if (!(await _androidPlugin?.areNotificationsEnabled() ?? true)) {
      throw StateError('Izin notifikasi belum aktif.');
    }
    await _plugin.show(
      id: 2147483000,
      title: 'Tes pengingat Routinity',
      body: 'Notifikasi berhasil muncul di perangkat ini.',
      notificationDetails: const NotificationDetails(android: _channel),
    );
  }

  Future<NotificationScheduleResult> schedule(
    Activity activity, {
    bool immediateReminder = false,
  }) async {
    if (kIsWeb) {
      return const NotificationScheduleResult(
        scheduled: false,
        message: 'Notifikasi tidak tersedia di web.',
      );
    }
    await initialize();
    final scheduledAt = immediateReminder
        ? activity.startAt
        : activity.startAt.subtract(
            Duration(minutes: activity.reminderMinutes),
          );
    if (!scheduledAt.isAfter(DateTime.now())) {
      return const NotificationScheduleResult(
        scheduled: false,
        message: 'Waktu pengingat sudah lewat. Pilih waktu yang akan datang.',
      );
    }
    if (!(await _androidPlugin?.areNotificationsEnabled() ?? true)) {
      return const NotificationScheduleResult(
        scheduled: false,
        message: 'Izin notifikasi belum aktif.',
      );
    }

    final exactEnabled =
        await _androidPlugin?.canScheduleExactNotifications() ?? true;
    final mode = exactEnabled
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    await _plugin.zonedSchedule(
      id: _notificationId(activity.id),
      title: activity.title,
      body: activity.reminderMinutes == 0 || immediateReminder
          ? 'Kegiatan dimulai sekarang • ${activity.category}'
          : 'Dimulai ${activity.reminderMinutes} menit lagi • ${activity.category}',
      scheduledDate: tz.TZDateTime.from(scheduledAt, tz.local),
      notificationDetails: const NotificationDetails(android: _channel),
      androidScheduleMode: mode,
      payload: activity.id,
    );

    final pending = await _plugin.pendingNotificationRequests();
    final stored = pending.any(
      (request) => request.id == _notificationId(activity.id),
    );
    return NotificationScheduleResult(
      scheduled: stored,
      usedExactAlarm: exactEnabled,
      message: stored
          ? exactEnabled
                ? 'Pengingat presisi berhasil dijadwalkan.'
                : 'Pengingat berhasil dijadwalkan tanpa mode presisi.'
          : 'Android tidak menyimpan pengingat. Periksa pengaturan notifikasi.',
    );
  }

  Future<void> cancel(String activityId) async {
    if (kIsWeb) return;
    await initialize();
    await _plugin.cancel(id: _notificationId(activityId));
  }

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  int _notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
