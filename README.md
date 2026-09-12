# Routinity

Routinity adalah aplikasi Flutter untuk mengelola jadwal dan rutinitas harian. Aplikasi menggunakan Google Login melalui Firebase Authentication, sementara data kegiatan tetap disimpan secara lokal di perangkat.

## Fitur

- Login dan logout dengan akun Google
- Jadwal kegiatan dan catatan
- Rutinitas berulang harian, hari kerja, atau mingguan
- Reminder, alarm, dan notifikasi lokal
- Status kegiatan: akan datang, berjalan, selesai, atau dilewati
- Kalender dan ringkasan progres
- Penyimpanan local-first/offline

## Teknologi

- Flutter / Dart
- Firebase Authentication
- Shared Preferences
- Flutter Local Notifications

## Konfigurasi

- Firebase project: `routinity-app-adi`
- Android package: `id.routinity.routinity`
- Minimum Android: Android 7.0 (API 24)

`android/app/google-services.json` berisi identifier konfigurasi publik Firebase untuk Android, bukan private key. Jangan pernah memasukkan service-account key, OAuth client secret, signing keystore, atau token ke repository.

Untuk memakai signing key Android yang berbeda, tambahkan fingerprint SHA-1 dan SHA-256 sertifikat tersebut pada aplikasi Android di Firebase Console.

## Menjalankan proyek

```bash
flutter pub get
flutter run
```

## Verifikasi

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

APK ARM64 akan tersedia di:

```text
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

## Privasi data

Login Google digunakan untuk identitas dan sesi pengguna. Jadwal, rutinitas, status aktivitas, dan progres belum disinkronkan ke cloud; data tersebut tetap berada pada perangkat yang digunakan.
