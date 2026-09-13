import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
  FirebaseGoogleAuthService({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
    : _auth = auth ?? FirebaseAuth.instance,
      _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  Future<void>? _googleInitialization;

  @override
  Stream<AuthSession?> authStateChanges() => _auth.authStateChanges().map(
    (user) => user == null ? null : FirebaseAuthSession(user),
  );

  @override
  Future<AuthSession?> signInWithGoogle() async {
    await (_googleInitialization ??= _googleSignIn.initialize());
    final account = await _googleSignIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google tidak mengembalikan token autentikasi.');
    }
    final googleCredential = GoogleAuthProvider.credential(idToken: idToken);
    final credential = await _auth.signInWithCredential(googleCredential);
    final user = credential.user;
    return user == null ? null : FirebaseAuthSession(user);
  }

  @override
  Future<void> signOut() async {
    await (_googleInitialization ??= _googleSignIn.initialize());
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
