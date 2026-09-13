import 'package:flutter_test/flutter_test.dart';
import 'package:routinity/models/activity.dart';
import 'package:routinity/services/notification_service.dart';

void main() {
  Activity activity({int reminder = 10, int duration = 60}) => Activity(
    id: 'jadwal-1',
    title: 'Belajar Flutter',
    category: 'Belajar',
    startAt: DateTime(2026, 9, 13, 10),
    durationMinutes: duration,
    reminderMinutes: reminder,
    status: ActivityStatus.scheduled,
    repeatRule: RepeatRule.none,
  );

  test('mode normal membuat pengingat awal dan saat mulai', () {
    final items = NotificationService.reminderScheduleFor(activity());
    expect(items.map((item) => item.time), [
      DateTime(2026, 9, 13, 9, 50),
      DateTime(2026, 9, 13, 10),
    ]);
  });

  test('mode berulang membuat dua tindak lanjut yang dibatasi durasi', () {
    final items = NotificationService.reminderScheduleFor(
      activity().copyWith(reminderMode: ReminderMode.persistent),
    );
    expect(items.map((item) => item.time), [
      DateTime(2026, 9, 13, 9, 50),
      DateTime(2026, 9, 13, 10),
      DateTime(2026, 9, 13, 10, 5),
      DateTime(2026, 9, 13, 10, 10),
    ]);
  });

  test('pengingat lanjutan tidak melewati akhir kegiatan', () {
    final items = NotificationService.reminderScheduleFor(
      activity(
        reminder: 0,
        duration: 10,
      ).copyWith(reminderMode: ReminderMode.persistent),
    );
    expect(items.map((item) => item.time), [
      DateTime(2026, 9, 13, 10),
      DateTime(2026, 9, 13, 10, 5),
    ]);
  });

  test('snooze hanya menjadwalkan satu pengingat pada waktu baru', () {
    final items = NotificationService.reminderScheduleFor(
      activity(),
      immediateReminder: true,
    );
    expect(items.first.time, DateTime(2026, 9, 13, 10));
    expect(items, hasLength(1));
  });

  test('jadwal berulang disiapkan tujuh hari ke depan', () {
    final source = activity(reminder: 0).copyWith(repeatRule: RepeatRule.daily);
    final occurrences = NotificationService.upcomingOccurrences(
      source,
      now: source.startAt.subtract(const Duration(minutes: 1)),
    );
    expect(occurrences, hasLength(7));
    expect(
      occurrences.last.startAt,
      source.startAt.add(const Duration(days: 6)),
    );
  });
}
