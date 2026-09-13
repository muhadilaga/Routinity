import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/activity.dart';
import '../services/activity_store.dart';

const _categories = ['Pribadi', 'Belajar', 'Kerja', 'Kesehatan', 'Ibadah'];
const _durations = [15, 30, 45, 60, 90, 120];
const _reminders = [0, 5, 10, 15, 30, 60];
const _weekdayLabels = {
  DateTime.monday: 'Sen',
  DateTime.tuesday: 'Sel',
  DateTime.wednesday: 'Rab',
  DateTime.thursday: 'Kam',
  DateTime.friday: 'Jum',
  DateTime.saturday: 'Sab',
  DateTime.sunday: 'Min',
};

Future<void> showActivityEditor(
  BuildContext context,
  ActivityStore store, {
  Activity? activity,
}) async {
  final editing = activity != null;
  final title = TextEditingController(text: activity?.title ?? '');
  final notes = TextEditingController(text: activity?.notes ?? '');
  var date = activity?.startAt ?? DateTime.now();
  var time = TimeOfDay.fromDateTime(activity?.startAt ?? DateTime.now());
  var duration = activity?.durationMinutes ?? 30;
  var reminder = activity?.reminderMinutes ?? 0;
  var category = activity?.category ?? 'Pribadi';
  var repeat = activity?.repeatRule ?? RepeatRule.none;
  var weekdays = <int>{...?activity?.repeatWeekdays};

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 22,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      editing ? 'Edit kegiatan' : 'Tambah kegiatan',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('activityTitleField'),
                controller: title,
                autofocus: !editing,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Nama kegiatan'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final firstDate = editing && date.isBefore(now)
                            ? DateTime(date.year, date.month, date.day)
                            : DateTime(now.year, now.month, now.day);
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: firstDate,
                          lastDate: now.add(const Duration(days: 730)),
                          initialDate: date.isBefore(firstDate)
                              ? firstDate
                              : date,
                        );
                        if (picked != null) setSheetState(() => date = picked);
                      },
                      icon: const Icon(Icons.calendar_today),
                      label: Text(DateFormat('d MMM yyyy').format(date)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: time,
                        );
                        if (picked != null) setSheetState(() => time = picked);
                      },
                      icon: const Icon(Icons.schedule),
                      label: Text(time.format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: duration,
                decoration: const InputDecoration(labelText: 'Durasi'),
                items: _durations
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text('$value menit'),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setSheetState(() => duration = value ?? 30),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: _categories
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setSheetState(() => category = value ?? 'Pribadi'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: reminder,
                decoration: const InputDecoration(labelText: 'Pengingat'),
                items: _reminders
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(
                          value == 0
                              ? 'Saat kegiatan dimulai'
                              : '$value menit sebelumnya',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setSheetState(() => reminder = value ?? 0),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<RepeatRule>(
                initialValue: repeat,
                decoration: const InputDecoration(labelText: 'Ulangi'),
                items: RepeatRule.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(repeatRuleLabel(value)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setSheetState(() {
                  repeat = value ?? RepeatRule.none;
                  if (repeat == RepeatRule.selectedDays && weekdays.isEmpty) {
                    weekdays = {date.weekday};
                  }
                }),
              ),
              if (repeat == RepeatRule.selectedDays) ...[
                const SizedBox(height: 12),
                const Text(
                  'Pilih hari',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: _weekdayLabels.entries
                      .map(
                        (entry) => FilterChip(
                          label: Text(entry.value),
                          selected: weekdays.contains(entry.key),
                          onSelected: (selected) => setSheetState(() {
                            if (selected) {
                              weekdays.add(entry.key);
                            } else if (weekdays.length > 1) {
                              weekdays.remove(entry.key);
                            }
                          }),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const Key('saveActivityButton'),
                onPressed: () async {
                  if (title.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Nama kegiatan wajib diisi.'),
                      ),
                    );
                    return;
                  }
                  if (repeat == RepeatRule.selectedDays && weekdays.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Pilih minimal satu hari.')),
                    );
                    return;
                  }
                  final start = DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  );
                  final reminderAt = start.subtract(
                    Duration(minutes: reminder),
                  );
                  if (!reminderAt.isAfter(DateTime.now())) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Waktu pengingat sudah lewat. Pilih jadwal lebih jauh atau ubah pengingat.',
                        ),
                      ),
                    );
                    return;
                  }
                  final result = Activity(
                    id:
                        activity?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    title: title.text.trim(),
                    notes: notes.text.trim(),
                    startAt: start,
                    durationMinutes: duration,
                    category: category,
                    reminderMinutes: reminder,
                    status: editing && activity.status != ActivityStatus.missed
                        ? activity.status
                        : ActivityStatus.scheduled,
                    repeatRule: repeat,
                    repeatWeekdays: repeat == RepeatRule.selectedDays
                        ? (weekdays.toList()..sort())
                        : const [],
                  );
                  if (editing) {
                    await store.update(result);
                  } else {
                    await store.add(result);
                  }
                  if (context.mounted) {
                    Navigator.pop(context);
                    final message = store.lastReminderMessage;
                    if (message != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(message),
                          backgroundColor: store.lastReminderScheduled
                              ? null
                              : Theme.of(context).colorScheme.error,
                        ),
                      );
                    }
                  }
                },
                icon: Icon(editing ? Icons.save_outlined : Icons.alarm_add),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    editing
                        ? 'Simpan perubahan'
                        : 'Simpan & aktifkan pengingat',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  title.dispose();
  notes.dispose();
}

Future<void> showRescheduleDialog(
  BuildContext context,
  ActivityStore store,
  Activity activity,
) async {
  var date = activity.startAt.isAfter(DateTime.now())
      ? activity.startAt
      : DateTime.now();
  var time = TimeOfDay.fromDateTime(date);
  final result = await showDialog<DateTime>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Jadwalkan ulang'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: Text(
                DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(date),
              ),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(now.year, now.month, now.day),
                  lastDate: now.add(const Duration(days: 730)),
                  initialDate: date,
                );
                if (picked != null) setDialogState(() => date = picked);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(time.format(context)),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: time,
                );
                if (picked != null) setDialogState(() => time = picked);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final selected = DateTime(
                date.year,
                date.month,
                date.day,
                time.hour,
                time.minute,
              );
              if (!selected.isAfter(DateTime.now())) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Pilih waktu yang akan datang.'),
                  ),
                );
                return;
              }
              Navigator.pop(context, selected);
            },
            child: const Text('Jadwalkan'),
          ),
        ],
      ),
    ),
  );
  if (result != null) await store.reschedule(activity, result);
}

String repeatRuleLabel(RepeatRule value) => switch (value) {
  RepeatRule.none => 'Tidak berulang',
  RepeatRule.daily => 'Setiap hari',
  RepeatRule.weekdays => 'Hari kerja',
  RepeatRule.weekly => 'Setiap minggu',
  RepeatRule.selectedDays => 'Hari tertentu',
};
