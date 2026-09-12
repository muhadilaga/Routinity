import 'dart:convert';

enum ActivityStatus { scheduled, completed, skipped }

enum RepeatRule { none, daily, weekdays, weekly }

class Activity {
  const Activity({
    required this.id,
    required this.title,
    required this.startAt,
    required this.durationMinutes,
    required this.category,
    required this.reminderMinutes,
    required this.status,
    required this.repeatRule,
    this.notes = '',
  });

  final String id;
  final String title;
  final DateTime startAt;
  final int durationMinutes;
  final String category;
  final int reminderMinutes;
  final ActivityStatus status;
  final RepeatRule repeatRule;
  final String notes;

  Activity copyWith({
    String? title,
    DateTime? startAt,
    int? durationMinutes,
    String? category,
    int? reminderMinutes,
    ActivityStatus? status,
    RepeatRule? repeatRule,
    String? notes,
  }) {
    return Activity(
      id: id,
      title: title ?? this.title,
      startAt: startAt ?? this.startAt,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      category: category ?? this.category,
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      status: status ?? this.status,
      repeatRule: repeatRule ?? this.repeatRule,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startAt': startAt.toIso8601String(),
    'durationMinutes': durationMinutes,
    'category': category,
    'reminderMinutes': reminderMinutes,
    'status': status.name,
    'repeatRule': repeatRule.name,
    'notes': notes,
  };

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
    id: json['id'] as String,
    title: json['title'] as String,
    startAt: DateTime.parse(json['startAt'] as String),
    durationMinutes: json['durationMinutes'] as int,
    category: json['category'] as String,
    reminderMinutes: json['reminderMinutes'] as int,
    status: ActivityStatus.values.byName(json['status'] as String),
    repeatRule: RepeatRule.values.byName(json['repeatRule'] as String),
    notes: json['notes'] as String? ?? '',
  );

  static String encodeList(List<Activity> items) =>
      jsonEncode(items.map((item) => item.toJson()).toList());

  static List<Activity> decodeList(String value) =>
      (jsonDecode(value) as List<dynamic>)
          .map((item) => Activity.fromJson(item as Map<String, dynamic>))
          .toList();
}
