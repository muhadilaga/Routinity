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
      final now = DateTime(2026, 9, 12, 6);
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

      final store = ActivityStore(NotificationService(), now: () => now);
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

  test('kegiatan yang sudah berakhir ditandai terlewat otomatis', () async {
    final now = DateTime(2026, 9, 12, 12);
    final item = Activity(
      id: 'missed-test',
      title: 'Kegiatan lama',
      startAt: DateTime(2026, 9, 12, 9),
      durationMinutes: 60,
      category: 'Pribadi',
      reminderMinutes: 10,
      status: ActivityStatus.scheduled,
      repeatRule: RepeatRule.none,
    );
    SharedPreferences.setMockInitialValues({
      'routinity.initialized.v1': true,
      'routinity.activities.v1': Activity.encodeList([item]),
    });

    final store = ActivityStore(NotificationService(), now: () => now);
    await store.load();
    expect(store.activities.single.status, ActivityStatus.missed);
  });

  test(
    'kegiatan terlewat dapat dijadwalkan ulang dan status kembali aktif',
    () async {
      final now = DateTime(2026, 9, 12, 12);
      final item = Activity(
        id: 'reschedule-test',
        title: 'Jadwalkan ulang',
        startAt: DateTime(2026, 9, 12, 9),
        durationMinutes: 30,
        category: 'Belajar',
        reminderMinutes: 5,
        status: ActivityStatus.missed,
        repeatRule: RepeatRule.none,
      );
      SharedPreferences.setMockInitialValues({
        'routinity.initialized.v1': true,
        'routinity.activities.v1': Activity.encodeList([item]),
      });
      final store = ActivityStore(NotificationService(), now: () => now);
      await store.load();

      final future = DateTime(2026, 9, 12, 15);
      await store.reschedule(store.activities.single, future);
      expect(store.activities.single.startAt, future);
      expect(store.activities.single.status, ActivityStatus.scheduled);
    },
  );

  test('rutinitas hari tertentu maju ke hari pilihan berikutnya', () async {
    final now = DateTime(2026, 9, 17, 8); // Kamis
    final item = Activity(
      id: 'selected-days-test',
      title: 'Senin dan Rabu',
      startAt: DateTime(2026, 9, 14, 7), // Senin
      durationMinutes: 30,
      category: 'Belajar',
      reminderMinutes: 5,
      status: ActivityStatus.completed,
      repeatRule: RepeatRule.selectedDays,
      repeatWeekdays: const [DateTime.monday, DateTime.wednesday],
    );
    SharedPreferences.setMockInitialValues({
      'routinity.initialized.v1': true,
      'routinity.activities.v1': Activity.encodeList([item]),
    });

    final store = ActivityStore(NotificationService(), now: () => now);
    await store.load();
    final refreshed = store.activities.single;
    expect(refreshed.startAt, DateTime(2026, 9, 21, 7));
    expect(refreshed.status, ActivityStatus.scheduled);
  });

  test('edit kegiatan mempertahankan id dan menyimpan perubahan', () async {
    final now = DateTime(2026, 9, 12, 8);
    final item = Activity(
      id: 'edit-test',
      title: 'Judul lama',
      startAt: DateTime(2026, 9, 12, 10),
      durationMinutes: 30,
      category: 'Pribadi',
      reminderMinutes: 10,
      status: ActivityStatus.scheduled,
      repeatRule: RepeatRule.none,
    );
    SharedPreferences.setMockInitialValues({
      'routinity.initialized.v1': true,
      'routinity.activities.v1': Activity.encodeList([item]),
    });
    final store = ActivityStore(NotificationService(), now: () => now);
    await store.load();

    await store.update(item.copyWith(title: 'Judul baru', durationMinutes: 60));
    expect(store.activities.single.id, 'edit-test');
    expect(store.activities.single.title, 'Judul baru');
    expect(store.activities.single.durationMinutes, 60);
  });
}
