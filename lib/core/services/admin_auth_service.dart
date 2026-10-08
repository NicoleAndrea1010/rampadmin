import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminAuthService {
  AdminAuthService(this._auth);

  final FirebaseAuth _auth;

  Stream<User?> get authStateChanges => _auth.idTokenChanges();

  User? get currentUser => _auth.currentUser;

  Future<User> signIn({required String email, required String password}) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );

    final user = credential.user;

    if (user == null) {
      throw StateError('Firebase did not return a user.');
    }

    try {
      final token = await user.getIdTokenResult(true);
      final role = token.claims?['role'];
      if (role == 'super_admin' || await _hasActiveAdminProfile(user.uid)) {
        return user;
      }
    } catch (_) {
      await _auth.signOut();
      rethrow;
    }

    await _auth.signOut();
    throw const AdminAccessException(
      'This account does not have super-admin access.',
    );
  }

  Future<bool> isCurrentUserSuperAdmin() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final token = await user.getIdTokenResult(true);
      if (token.claims?['role'] == 'super_admin') return true;
      return await _hasActiveAdminProfile(user.uid);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasActiveAdminProfile(String uid) async {
    final profile = await FirebaseFirestore.instance
        .collection('adminProfiles')
        .doc(uid)
        .get()
        .timeout(const Duration(seconds: 5));
    return profile.exists && profile.data()?['status'] == 'active';
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
  }

  Future<void> signOut() => _auth.signOut();
}

class AdminAccessException implements Exception {
  const AdminAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}
