import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/activity.dart';
import 'notification_service.dart';

class ActivityStore extends ChangeNotifier {
  ActivityStore(this._notifications, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const _storageKey = 'routinity.activities.v1';
  static const _initializedKey = 'routinity.initialized.v1';
  final NotificationService _notifications;
  final DateTime Function() _now;
  final List<Activity> _activities = [];

  List<Activity> get activities => List.unmodifiable(_activities);
  List<Activity> conflictsFor(Activity candidate) => _activities.where((item) {
    if (item.id == candidate.id || item.status != ActivityStatus.scheduled) {
      return false;
    }
    return candidate.startAt.isBefore(item.endAt) &&
        candidate.endAt.isAfter(item.startAt);
  }).toList();
  NotificationService get notifications => _notifications;
  String? _lastReminderMessage;
  bool _lastReminderScheduled = true;
  String? get lastReminderMessage => _lastReminderMessage;
  bool get lastReminderScheduled => _lastReminderScheduled;

  Future<void> refreshStatuses() async {
    final before = Activity.encodeList(_activities);
    _refreshRecurringActivities();
    _markMissedActivities();
    if (Activity.encodeList(_activities) == before) return;
    await _persist();
    for (final item in _activities.where(
      (activity) => activity.status == ActivityStatus.scheduled,
    )) {
      await _scheduleSafely(item);
    }
    notifyListeners();
  }

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_storageKey);
    if (saved != null) {
      try {
        _activities
          ..clear()
          ..addAll(Activity.decodeList(saved));
      } catch (_) {
        _activities.clear();
      }
    }

    _refreshRecurringActivities();
    _markMissedActivities();
    if (_activities.isEmpty &&
        !(preferences.getBool(_initializedKey) ?? false)) {
      _activities.addAll(_sampleActivities());
      await preferences.setBool(_initializedKey, true);
      await _persist();
    } else if (_activities.isNotEmpty) {
      await _persist();
    }
    for (final item in _activities.where(
      (activity) => activity.status == ActivityStatus.scheduled,
    )) {
      await _scheduleSafely(item);
    }
    notifyListeners();
  }

  String exportJson() => Activity.encodeList(_activities);

  Future<int> importJson(String value, {bool merge = true}) async {
    final incoming = Activity.decodeList(value);
    final ids = <String>{};
    for (final item in incoming) {
      if (item.id.trim().isEmpty ||
          item.title.trim().isEmpty ||
          !ids.add(item.id)) {
        throw const FormatException(
          'Data cadangan tidak valid atau memiliki ID ganda.',
        );
      }
    }
    final next = merge ? [..._activities] : <Activity>[];
    for (final item in incoming) {
      final index = next.indexWhere((existing) => existing.id == item.id);
      if (index >= 0) {
        next[index] = item;
      } else {
        next.add(item);
      }
    }
    // Persistensikan hasil tervalidasi lebih dahulu. Jika penulisan gagal,
    // daftar aktif dan notifikasinya tidak diubah.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, Activity.encodeList(next));
    for (final old in _activities) {
      await _cancelSafely(old.id);
    }
    _activities
      ..clear()
      ..addAll(next);
    for (final item in _activities.where(
      (entry) => entry.status == ActivityStatus.scheduled,
    )) {
      await _scheduleSafely(item);
    }
    notifyListeners();
    return incoming.length;
  }

  Future<void> handleNotificationResponse(NotificationResponse response) async {
    final id = response.payload;
    if (id == null) return;
    final index = _activities.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final item = _activities[index];
    if (response.actionId == notificationActionDone) {
      await updateStatus(item, ActivityStatus.completed);
    } else if (response.actionId == notificationActionSkip) {
      await updateStatus(item, ActivityStatus.skipped);
    } else if (response.actionId == notificationActionSnooze) {
      await snooze(item, const Duration(minutes: 10));
    }
  }

  Future<void> add(Activity activity) async {
    _activities.add(activity);
    await _persist();
    await _scheduleSafely(activity);
    notifyListeners();
  }

  Future<void> update(Activity activity) async {
    final index = _activities.indexWhere((item) => item.id == activity.id);
    if (index < 0) return;
    await _cancelSafely(activity.id);
    final updated =
        activity.status == ActivityStatus.scheduled &&
            activity.endAt.isBefore(_now())
        ? activity.copyWith(status: ActivityStatus.missed)
        : activity;
    _activities[index] = updated;
    await _persist();
    if (updated.status == ActivityStatus.scheduled) {
      await _scheduleSafely(updated);
    }
    notifyListeners();
  }

  Future<void> updateStatus(Activity activity, ActivityStatus status) async {
    final index = _activities.indexWhere((item) => item.id == activity.id);
    if (index < 0) return;
    _activities[index] = activity.copyWith(status: status);
    if (status != ActivityStatus.scheduled) {
      await _cancelSafely(activity.id);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> skipAll(Iterable<Activity> activities) async {
    for (final activity in activities.toList()) {
      await updateStatus(activity, ActivityStatus.skipped);
    }
  }

  Future<void> snooze(Activity activity, Duration duration) async {
    await reschedule(activity, _now().add(duration), immediateReminder: true);
  }

  Future<void> reschedule(
    Activity activity,
    DateTime startAt, {
    bool immediateReminder = false,
  }) async {
    final updated = activity.copyWith(
      startAt: startAt,
      status: ActivityStatus.scheduled,
    );
    final index = _activities.indexWhere((item) => item.id == activity.id);
    if (index < 0) return;
    await _cancelSafely(activity.id);
    _activities[index] = updated;
    await _persist();
    await _scheduleSafely(updated, immediateReminder: immediateReminder);
    notifyListeners();
  }

  Future<void> delete(Activity activity) async {
    _activities.removeWhere((item) => item.id == activity.id);
    await _cancelSafely(activity.id);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, Activity.encodeList(_activities));
  }

  Future<void> _scheduleSafely(
    Activity activity, {
    bool immediateReminder = false,
  }) async {
    try {
      final result = await _notifications.schedule(
        activity,
        immediateReminder: immediateReminder,
      );
      _lastReminderScheduled = result.scheduled;
      _lastReminderMessage = result.message;
    } catch (error) {
      _lastReminderScheduled = false;
      _lastReminderMessage = 'Pengingat gagal dijadwalkan: $error';
      debugPrint('Pengingat tidak dapat dijadwalkan: $error');
    }
  }

  Future<void> _cancelSafely(String activityId) async {
    try {
      await _notifications.cancel(activityId);
    } catch (error) {
      debugPrint('Pengingat tidak dapat dibatalkan: $error');
    }
  }

  void _refreshRecurringActivities() {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    for (var index = 0; index < _activities.length; index++) {
      var item = _activities[index];
      if (item.repeatRule == RepeatRule.none || !item.startAt.isBefore(today)) {
        continue;
      }
      var next = item.startAt;
      do {
        next = _nextOccurrence(next, item.repeatRule, item.repeatWeekdays);
      } while (next.isBefore(today));
      item = item.copyWith(startAt: next, status: ActivityStatus.scheduled);
      _activities[index] = item;
    }
  }

  void _markMissedActivities() {
    final now = _now();
    for (var index = 0; index < _activities.length; index++) {
      final item = _activities[index];
      if (item.status == ActivityStatus.scheduled && item.endAt.isBefore(now)) {
        _activities[index] = item.copyWith(status: ActivityStatus.missed);
      }
    }
  }

  DateTime _nextOccurrence(
    DateTime from,
    RepeatRule rule,
    List<int> repeatWeekdays,
  ) {
    if (rule == RepeatRule.weekly) return from.add(const Duration(days: 7));
    var next = from.add(const Duration(days: 1));
    if (rule == RepeatRule.weekdays) {
      while (next.weekday == DateTime.saturday ||
          next.weekday == DateTime.sunday) {
        next = next.add(const Duration(days: 1));
      }
    } else if (rule == RepeatRule.selectedDays) {
      if (repeatWeekdays.isEmpty) return from.add(const Duration(days: 7));
      while (!repeatWeekdays.contains(next.weekday)) {
        next = next.add(const Duration(days: 1));
      }
    }
    return next;
  }

  List<Activity> _sampleActivities() {
    final now = _now();
    final base = DateTime(now.year, now.month, now.day);
    return [
      Activity(
        id: 'sample-focus',
        title: 'Fokus mengerjakan tugas',
        startAt: base.add(const Duration(hours: 9)),
        durationMinutes: 90,
        category: 'Belajar',
        reminderMinutes: 10,
        status: ActivityStatus.scheduled,
        repeatRule: RepeatRule.weekdays,
      ),
      Activity(
        id: 'sample-exercise',
        title: 'Olahraga ringan',
        startAt: base.add(const Duration(hours: 17, minutes: 30)),
        durationMinutes: 30,
        category: 'Kesehatan',
        reminderMinutes: 15,
        status: ActivityStatus.scheduled,
        repeatRule: RepeatRule.daily,
      ),
    ];
  }
}
