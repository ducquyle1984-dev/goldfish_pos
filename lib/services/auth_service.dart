import 'package:firebase_auth/firebase_auth.dart';

/// Wrapper around `FirebaseAuth` operations to keep UI code clean.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<UserCredential> signIn(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() => _auth.signOut();

  Stream<User?> get authStateChanges => _auth.authStateChanges();
}
