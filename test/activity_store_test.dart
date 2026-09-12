import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:routinity/models/activity.dart';
import 'package:routinity/services/activity_store.dart';
import 'package:routinity/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'data contoh hanya dibuat sekali dan tidak kembali setelah dihapus',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = ActivityStore(NotificationService());
      await first.load();
      expect(first.activities, hasLength(2));

      for (final item in [...first.activities]) {
        await first.delete(item);
      }
      expect(first.activities, isEmpty);

      final reloaded = ActivityStore(NotificationService());
      await reloaded.load();
      expect(reloaded.activities, isEmpty);
    },
  );

  test(
    'rutinitas harian lama digeser ke hari ini dan status direset',
    () async {
      final now = DateTime.now();
      final old = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 3)).add(const Duration(hours: 7));
      final item = Activity(
        id: 'daily-test',
        title: 'Rutinitas harian',
        startAt: old,
        durationMinutes: 30,
        category: 'Pribadi',
        reminderMinutes: 10,
        status: ActivityStatus.completed,
        repeatRule: RepeatRule.daily,
      );
      SharedPreferences.setMockInitialValues({
        'routinity.initialized.v1': true,
        'routinity.activities.v1': Activity.encodeList([item]),
      });

      final store = ActivityStore(NotificationService());
      await store.load();
      final refreshed = store.activities.single;
      expect(refreshed.startAt.year, now.year);
      expect(refreshed.startAt.month, now.month);
      expect(refreshed.startAt.day, now.day);
      expect(refreshed.status, ActivityStatus.scheduled);
    },
  );

  test('rutinitas hari kerja tidak dijadwalkan pada akhir pekan', () async {
    final friday = DateTime(2026, 9, 11, 8);
    final item = Activity(
      id: 'weekday-test',
      title: 'Rutinitas kerja',
      startAt: friday,
      durationMinutes: 30,
      category: 'Kerja',
      reminderMinutes: 5,
      status: ActivityStatus.completed,
      repeatRule: RepeatRule.weekdays,
    );
    SharedPreferences.setMockInitialValues({
      'routinity.initialized.v1': true,
      'routinity.activities.v1': Activity.encodeList([item]),
    });

    final store = ActivityStore(NotificationService());
    await store.load();
    final refreshed = store.activities.single;
    expect(refreshed.startAt.weekday, isNot(DateTime.saturday));
    expect(refreshed.startAt.weekday, isNot(DateTime.sunday));
  });
}
