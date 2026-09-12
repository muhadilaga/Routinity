import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/activity.dart';
import 'notification_service.dart';

class ActivityStore extends ChangeNotifier {
  ActivityStore(this._notifications);

  static const _storageKey = 'routinity.activities.v1';
  static const _initializedKey = 'routinity.initialized.v1';
  final NotificationService _notifications;
  final List<Activity> _activities = [];

  List<Activity> get activities => List.unmodifiable(_activities);

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

  Future<void> add(Activity activity) async {
    _activities.add(activity);
    await _persist();
    await _scheduleSafely(activity);
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

  Future<void> snooze(Activity activity, Duration duration) async {
    final index = _activities.indexWhere((item) => item.id == activity.id);
    if (index < 0) return;
    final updated = activity.copyWith(
      startAt: DateTime.now().add(duration),
      status: ActivityStatus.scheduled,
    );
    _activities[index] = updated;
    await _persist();
    await _scheduleSafely(updated, immediateReminder: true);
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
      await _notifications.schedule(
        activity,
        immediateReminder: immediateReminder,
      );
    } catch (error) {
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (var index = 0; index < _activities.length; index++) {
      var item = _activities[index];
      if (item.repeatRule == RepeatRule.none || !item.startAt.isBefore(today)) {
        continue;
      }
      var next = item.startAt;
      do {
        next = _nextOccurrence(next, item.repeatRule);
      } while (next.isBefore(today));
      item = item.copyWith(startAt: next, status: ActivityStatus.scheduled);
      _activities[index] = item;
    }
  }

  DateTime _nextOccurrence(DateTime from, RepeatRule rule) {
    if (rule == RepeatRule.weekly) return from.add(const Duration(days: 7));
    var next = from.add(const Duration(days: 1));
    if (rule == RepeatRule.weekdays) {
      while (next.weekday == DateTime.saturday ||
          next.weekday == DateTime.sunday) {
        next = next.add(const Duration(days: 1));
      }
    }
    return next;
  }

  List<Activity> _sampleActivities() {
    final now = DateTime.now();
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
