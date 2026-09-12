import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:routinity/main.dart';
import 'package:routinity/services/activity_store.dart';
import 'package:routinity/services/auth_service.dart';
import 'package:routinity/services/notification_service.dart';

class _TestSession implements AuthSession {
  @override
  String? get displayName => 'Adi';
  @override
  String? get email => 'adi@example.com';
  @override
  String? get photoUrl => null;
}

class _TestAuthService implements AuthService {
  _TestAuthService(this.session);
  final AuthSession? session;

  @override
  Stream<AuthSession?> authStateChanges() => Stream.value(session);

  @override
  Future<AuthSession?> signInWithGoogle() async => session;

  @override
  Future<void> signOut() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('menampilkan dashboard dan dapat membuka form kegiatan', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = ActivityStore(NotificationService());
    await store.load();
    await initializeDateFormatting('id_ID');

    await tester.pumpWidget(
      RoutinityApp(store: store, authService: _TestAuthService(_TestSession())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hari ini'), findsWidgets);
    expect(find.text('Progres hari ini'), findsOneWidget);
    expect(find.byKey(const Key('addActivityButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('addActivityButton')));
    await tester.pumpAndSettle();

    expect(find.text('Tambah kegiatan'), findsOneWidget);
    expect(find.byKey(const Key('activityTitleField')), findsOneWidget);
    expect(find.byKey(const Key('saveActivityButton')), findsOneWidget);
  });

  testWidgets('menampilkan login Google saat belum memiliki sesi', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = ActivityStore(NotificationService());
    await store.load();
    await initializeDateFormatting('id_ID');

    await tester.pumpWidget(
      RoutinityApp(store: store, authService: _TestAuthService(null)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selamat datang di Routinity'), findsOneWidget);
    expect(find.byKey(const Key('googleSignInButton')), findsOneWidget);
    expect(find.byKey(const Key('addActivityButton')), findsNothing);
  });
}
