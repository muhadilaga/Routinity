import 'package:flutter_test/flutter_test.dart';
import 'package:routinity/models/activity.dart';

void main() {
  test('activity list dapat disimpan dan dipulihkan tanpa kehilangan data', () {
    final activity = Activity(
      id: 'test-1',
      title: 'Belajar Flutter',
      startAt: DateTime(2026, 9, 10, 9),
      durationMinutes: 60,
      category: 'Belajar',
      reminderMinutes: 10,
      status: ActivityStatus.completed,
      repeatRule: RepeatRule.weekdays,
      notes: 'Bab widget',
    );

    final decoded = Activity.decodeList(Activity.encodeList([activity])).single;
    expect(decoded.title, activity.title);
    expect(decoded.startAt, activity.startAt);
    expect(decoded.status, ActivityStatus.completed);
    expect(decoded.repeatRule, RepeatRule.weekdays);
    expect(decoded.notes, 'Bab widget');
  });
}
