import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/activity.dart';
import 'activity_store.dart';

const notificationActionDone = 'routinity.done';
const notificationActionSnooze = 'routinity.snooze';
const notificationActionSkip = 'routinity.skip';

@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  final notifications = NotificationService();
  final store = ActivityStore(notifications);
  await store.load();
  await store.handleNotificationResponse(response);
}

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
    ongoing: true,
    autoCancel: false,
    actions: [
      AndroidNotificationAction(notificationActionDone, 'Selesai'),
      AndroidNotificationAction(
        notificationActionSnooze,
        'Tunda 10m',
        cancelNotification: false,
      ),
      AndroidNotificationAction(notificationActionSkip, 'Lewati'),
    ],
  );

  // Satu kegiatan tidak hanya mengandalkan satu bunyi. Selain pengingat awal,
  // Android juga mengingatkan saat mulai serta 5 dan 10 menit sesudahnya
  // (selama kegiatan belum berakhir). Menandai selesai/lewati akan membatalkan
  // seluruh rangkaian ini.
  static const _followUpMinutes = [5, 10];
  static const _recurringHorizonDays = 7;

  void Function(NotificationResponse response)? onResponse;

  Future<void> initialize() async {
    if (kIsWeb || _initialized) return;
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) =>
          onResponse?.call(response),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
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
    final now = DateTime.now();
    final occurrences = immediateReminder
        ? [activity]
        : upcomingOccurrences(activity, now: now);
    final scheduleItems = <ReminderScheduleItem>[
      for (final occurrence in occurrences)
        ...reminderScheduleFor(
          occurrence,
          immediateReminder: immediateReminder,
        ).where((item) => item.time.isAfter(now)),
    ];
    if (scheduleItems.isEmpty) {
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

    // Bersihkan format ID versi lama dan rangkaian lama sebelum menjadwalkan
    // ulang agar hasil edit/snooze tidak menyisakan notifikasi yatim.
    await cancel(activity.id);
    for (var index = 0; index < scheduleItems.length; index++) {
      final item = scheduleItems[index];
      await _plugin.zonedSchedule(
        id: _notificationId(activity.id, item.time, index),
        title: activity.title,
        body: '${item.message} • ${activity.category}',
        scheduledDate: tz.TZDateTime.from(item.time, tz.local),
        notificationDetails: const NotificationDetails(android: _channel),
        androidScheduleMode: mode,
        payload: activity.id,
      );
    }

    final pending = await _plugin.pendingNotificationRequests();
    final expectedIds = {
      for (var index = 0; index < scheduleItems.length; index++)
        _notificationId(activity.id, scheduleItems[index].time, index),
    };
    final storedCount = pending
        .where((request) => expectedIds.contains(request.id))
        .length;
    final stored = storedCount == expectedIds.length;
    return NotificationScheduleResult(
      scheduled: stored,
      usedExactAlarm: exactEnabled,
      message: stored
          ? exactEnabled
                ? '$storedCount pengingat bertahap berhasil dijadwalkan.'
                : '$storedCount pengingat bertahap dijadwalkan tanpa mode presisi.'
          : 'Android tidak menyimpan pengingat. Periksa pengaturan notifikasi.',
    );
  }

  Future<void> cancel(String activityId) async {
    if (kIsWeb) return;
    await initialize();
    // Batalkan ID versi lama lalu semua tahap/kemunculan baru lewat payload.
    await _plugin.cancel(id: _legacyNotificationId(activityId));
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending.where((item) => item.payload == activityId)) {
      await _plugin.cancel(id: request.id);
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  static List<ReminderScheduleItem> reminderScheduleFor(
    Activity activity, {
    bool immediateReminder = false,
  }) {
    if (immediateReminder || activity.reminderMode == ReminderMode.once) {
      final time = immediateReminder
          ? activity.startAt
          : activity.startAt.subtract(
              Duration(minutes: activity.reminderMinutes),
            );
      return [
        ReminderScheduleItem(
          time: time,
          message: immediateReminder || activity.reminderMinutes == 0
              ? 'Kegiatan dimulai sekarang'
              : 'Dimulai ${activity.reminderMinutes} menit lagi',
        ),
      ];
    }

    final items = <ReminderScheduleItem>[];
    if (activity.reminderMinutes > 0) {
      items.add(
        ReminderScheduleItem(
          time: activity.startAt.subtract(
            Duration(minutes: activity.reminderMinutes),
          ),
          message: 'Dimulai ${activity.reminderMinutes} menit lagi',
        ),
      );
    }
    items.add(
      ReminderScheduleItem(
        time: activity.startAt,
        message: 'Kegiatan dimulai sekarang',
      ),
    );
    if (activity.reminderMode == ReminderMode.persistent) {
      items.addAll(
        _followUpMinutes
            .map(
              (minutes) => ReminderScheduleItem(
                time: activity.startAt.add(Duration(minutes: minutes)),
                message: 'Belum ditandai selesai — sudah lewat $minutes menit',
              ),
            )
            .where((item) => item.time.isBefore(activity.endAt)),
      );
    }
    return items;
  }

  static List<Activity> upcomingOccurrences(
    Activity activity, {
    required DateTime now,
  }) {
    if (activity.repeatRule == RepeatRule.none) return [activity];
    final horizon = now.add(const Duration(days: _recurringHorizonDays));
    final result = <Activity>[];
    var occurrence = activity.startAt;
    while (occurrence
        .add(Duration(minutes: activity.durationMinutes))
        .isBefore(now)) {
      occurrence = _nextOccurrence(
        occurrence,
        activity.repeatRule,
        activity.repeatWeekdays,
      );
    }
    while (!occurrence.isAfter(horizon)) {
      result.add(activity.copyWith(startAt: occurrence));
      occurrence = _nextOccurrence(
        occurrence,
        activity.repeatRule,
        activity.repeatWeekdays,
      );
    }
    return result;
  }

  static DateTime _nextOccurrence(
    DateTime from,
    RepeatRule rule,
    List<int> weekdays,
  ) {
    if (rule == RepeatRule.weekly) return from.add(const Duration(days: 7));
    var next = from.add(const Duration(days: 1));
    if (rule == RepeatRule.weekdays) {
      while (next.weekday > DateTime.friday) {
        next = next.add(const Duration(days: 1));
      }
    } else if (rule == RepeatRule.selectedDays && weekdays.isNotEmpty) {
      while (!weekdays.contains(next.weekday)) {
        next = next.add(const Duration(days: 1));
      }
    }
    return next;
  }

  int _notificationId(String value, DateTime time, int slot) =>
      _legacyNotificationId('$value:${time.millisecondsSinceEpoch}:$slot');

  int _legacyNotificationId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}

class ReminderScheduleItem {
  const ReminderScheduleItem({required this.time, required this.message});

  final DateTime time;
  final String message;
}
