import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'models/activity.dart';
import 'services/activity_store.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'widgets/activity_editor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await initializeDateFormatting('id_ID');
  final notifications = NotificationService();
  await notifications.initialize();
  final store = ActivityStore(notifications);
  await store.load();
  runApp(RoutinityApp(store: store, authService: FirebaseGoogleAuthService()));
}

class RoutinityApp extends StatelessWidget {
  const RoutinityApp({
    super.key,
    required this.store,
    required this.authService,
  });
  final ActivityStore store;
  final AuthService authService;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Routinity',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: AuthGate(store: store, authService: authService),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.store, required this.authService});

  final ActivityStore store;
  final AuthService authService;

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthSession?>(
    stream: authService.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final session = snapshot.data;
      if (session == null) return LoginPage(authService: authService);
      return HomeShell(
        store: store,
        authService: authService,
        session: session,
      );
    },
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.authService});
  final AuthService authService;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.authService.signInWithGoogle();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Login belum berhasil. Periksa koneksi lalu coba lagi.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(
                    Icons.task_alt_rounded,
                    color: Colors.white,
                    size: 52,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Selamat datang di Routinity',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Kelola jadwal, rutinitas, dan progres harianmu dalam satu tempat.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 34),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.tonalIcon(
                    key: const Key('googleSignInButton'),
                    onPressed: _loading ? null : _signIn,
                    icon: _loading
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'G',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                    label: Text(
                      _loading ? 'Menghubungkan...' : 'Lanjutkan dengan Google',
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    key: const Key('loginError'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  'Data kegiatan tetap disimpan secara lokal di perangkat ini.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.store,
    required this.authService,
    required this.session,
  });
  final ActivityStore store;
  final AuthService authService;
  final AuthSession session;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.store.refreshStatuses();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayPage(store: widget.store),
      CalendarPage(store: widget.store),
      ProgressPage(store: widget.store),
      SettingsPage(
        authService: widget.authService,
        session: widget.session,
        notifications: widget.store.notifications,
      ),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_index]),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addActivityButton'),
        onPressed: () => showActivityEditor(context, widget.store),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Kegiatan'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Hari ini',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Kalender',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Progres',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Pengaturan',
          ),
        ],
      ),
    );
  }
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.store});
  final ActivityStore store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final now = DateTime.now();
      final items =
          store.activities.where((item) => _sameDay(item.startAt, now)).toList()
            ..sort((a, b) => a.startAt.compareTo(b.startAt));
      final completed = items
          .where((item) => item.status == ActivityStatus.completed)
          .length;
      final progress = items.isEmpty ? 0.0 : completed / items.length;
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('EEEE, d MMMM', 'id_ID').format(now),
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Hari ini',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 18),
                  _SummaryCard(
                    completed: completed,
                    total: items.length,
                    progress: progress,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Jadwalmu',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          if (items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    ActivityCard(activity: items[index], store: store),
              ),
            ),
        ],
      );
    },
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.completed,
    required this.total,
    required this.progress,
  });
  final int completed;
  final int total;
  final double progress;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF6750A4), Color(0xFF8B74C8)],
      ),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Progres hari ini',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Text(
                '$completed dari $total selesai',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
                backgroundColor: Colors.white24,
                color: const Color(0xFFD7C7FF),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Text(
          '${(progress * 100).round()}%',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 26,
          ),
        ),
      ],
    ),
  );
}

class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.activity, required this.store});
  final Activity activity;
  final ActivityStore store;

  @override
  Widget build(BuildContext context) {
    final done = activity.status == ActivityStatus.completed;
    final skipped = activity.status == ActivityStatus.skipped;
    final missed = activity.status == ActivityStatus.missed;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0EBFA),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                children: [
                  Text(
                    DateFormat('HH:mm').format(activity.startAt),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${activity.durationMinutes}m',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      decoration: done || skipped
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${activity.category} • ${repeatRuleLabel(activity.repeatRule)}',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  if (!done && !skipped && !missed) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => store.updateStatus(
                            activity,
                            ActivityStatus.completed,
                          ),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Selesai'),
                        ),
                        OutlinedButton(
                          onPressed: () => store.snooze(
                            activity,
                            const Duration(minutes: 10),
                          ),
                          child: const Text('Tunda 10m'),
                        ),
                        IconButton(
                          tooltip: 'Lewati',
                          onPressed: () => store.updateStatus(
                            activity,
                            ActivityStatus.skipped,
                          ),
                          icon: const Icon(Icons.skip_next_outlined),
                        ),
                      ],
                    ),
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Text(
                        done
                            ? 'Selesai'
                            : skipped
                            ? 'Dilewati'
                            : 'Terlewat',
                        style: TextStyle(
                          color: done
                              ? Colors.green.shade700
                              : missed
                              ? Colors.red.shade700
                              : Colors.orange.shade800,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (missed)
                      TextButton.icon(
                        onPressed: () =>
                            showRescheduleDialog(context, store, activity),
                        icon: const Icon(Icons.event_repeat, size: 18),
                        label: const Text('Jadwalkan ulang'),
                      ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  showActivityEditor(context, store, activity: activity);
                } else if (value == 'reschedule') {
                  showRescheduleDialog(context, store, activity);
                } else if (value == 'delete') {
                  store.delete(activity);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                  value: 'reschedule',
                  child: Text('Jadwalkan ulang'),
                ),
                PopupMenuItem(value: 'delete', child: Text('Hapus')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key, required this.store});
  final ActivityStore store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final items = [...store.activities]
        ..sort((a, b) => a.startAt.compareTo(b.startAt));
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
        children: [
          Text(
            'Kalender',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Semua kegiatan yang sudah dijadwalkan.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 22),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ActivityCard(activity: item, store: store),
            ),
          ),
        ],
      );
    },
  );
}

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key, required this.store});
  final ActivityStore store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final total = store.activities.length;
      final done = store.activities
          .where((e) => e.status == ActivityStatus.completed)
          .length;
      final skipped = store.activities
          .where((e) => e.status == ActivityStatus.skipped)
          .length;
      final missed = store.activities
          .where((e) => e.status == ActivityStatus.missed)
          .length;
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
        children: [
          Text(
            'Progres',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pantau konsistensi rutinitasmu.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'Selesai',
                  value: '$done',
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Metric(
                  label: 'Dilewati',
                  value: '$skipped',
                  icon: Icons.skip_next_outlined,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Metric(
            label: 'Terlewat',
            value: '$missed',
            icon: Icons.warning_amber_rounded,
            color: Colors.red,
          ),
          const SizedBox(height: 12),
          _Metric(
            label: 'Tingkat penyelesaian',
            value: total == 0 ? '0%' : '${(done / total * 100).round()}%',
            icon: Icons.insights,
            color: AppTheme.primary,
          ),
        ],
      );
    },
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.authService,
    required this.session,
    required this.notifications,
  });
  final AuthService authService;
  final AuthSession session;
  final NotificationService notifications;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  NotificationPermissionStatus? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final value = await widget.notifications.getStatus();
      if (mounted) setState(() => _status = value);
    } catch (_) {
      // Plugin native tidak tersedia pada widget test dan platform non-Android.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestPermissions() async {
    setState(() => _loading = true);
    try {
      final value = await widget.notifications.requestPermissions();
      if (mounted) setState(() => _status = value);
    } catch (error) {
      _message('Tidak dapat membuka izin: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _testNotification() async {
    try {
      await widget.notifications.showTestNotification();
      _message('Notifikasi tes sudah dikirim. Periksa panel notifikasi HP.');
    } catch (error) {
      _message('Tes gagal: $error');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
    children: [
      Text(
        'Pengaturan',
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 22),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                child: Text(
                  (widget.session.displayName ?? widget.session.email ?? 'G')
                      .characters
                      .first
                      .toUpperCase(),
                ),
              ),
              title: Text(widget.session.displayName ?? 'Akun Google'),
              subtitle: Text(widget.session.email ?? ''),
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('signOutButton'),
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Keluar dari akun'),
              onTap: () => widget.authService.signOut(),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Card(
        child: Column(
          children: [
            ListTile(
              key: const Key('notificationPermissionTile'),
              leading: Icon(
                _status?.notificationsEnabled == true
                    ? Icons.notifications_active
                    : Icons.notifications_off_outlined,
              ),
              title: const Text('Izin notifikasi'),
              subtitle: Text(
                _loading
                    ? 'Memeriksa status…'
                    : _status?.notificationsEnabled == true
                    ? 'Aktif'
                    : 'Belum aktif — ketuk untuk mengizinkan',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _loading ? null : _requestPermissions,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.alarm_on_outlined),
              title: const Text('Alarm presisi'),
              subtitle: Text(
                _status?.exactAlarmsEnabled == true
                    ? 'Aktif — pengingat tepat waktu'
                    : 'Tidak aktif — memakai pengingat fleksibel',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _requestPermissions,
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('testNotificationButton'),
              leading: const Icon(Icons.send_outlined),
              title: const Text('Kirim notifikasi tes'),
              subtitle: Text(
                '${_status?.pendingCount ?? 0} pengingat tersimpan di Android',
              ),
              onTap: _testNotification,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('Pengaturan notifikasi Android'),
              subtitle: const Text('Atur suara, getaran, dan tampilan'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => widget.notifications.openNotificationSettings(),
            ),
            const Divider(height: 1),
            const ListTile(
              leading: Icon(Icons.storage_outlined),
              title: Text('Penyimpanan'),
              subtitle: Text('Offline di perangkat ini'),
            ),
            const Divider(height: 1),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Tentang Routinity'),
              subtitle: Text('Versi 1.1.1'),
            ),
          ],
        ),
      ),
    ],
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_available, size: 54, color: AppTheme.primary),
          SizedBox(height: 14),
          Text(
            'Belum ada kegiatan hari ini',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          SizedBox(height: 6),
          Text('Tambahkan kegiatan pertamamu.', textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
