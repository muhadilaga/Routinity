import 'package:firebase_auth/firebase_auth.dart';

abstract class AuthSession {
  String? get displayName;
  String? get email;
  String? get photoUrl;
}

class FirebaseAuthSession implements AuthSession {
  FirebaseAuthSession(this.user);

  final User user;

  @override
  String? get displayName => user.displayName;

  @override
  String? get email => user.email;

  @override
  String? get photoUrl => user.photoURL;
}

abstract class AuthService {
  Stream<AuthSession?> authStateChanges();
  Future<AuthSession?> signInWithGoogle();
  Future<void> signOut();
}

class FirebaseGoogleAuthService implements AuthService {
  FirebaseGoogleAuthService({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  Stream<AuthSession?> authStateChanges() => _auth.authStateChanges().map(
    (user) => user == null ? null : FirebaseAuthSession(user),
  );

  @override
  Future<AuthSession?> signInWithGoogle() async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    final credential = await _auth.signInWithProvider(provider);
    final user = credential.user;
    return user == null ? null : FirebaseAuthSession(user);
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
