import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/admin_auth_service.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final adminAuthServiceProvider = Provider<AdminAuthService>((ref) {
  return AdminAuthService(ref.watch(firebaseAuthProvider));
});

final currentAdminUserProvider = Provider<User?>((ref) {
  if (Firebase.apps.isEmpty) return null;
  ref.watch(authStateProvider);
  return ref.watch(firebaseAuthProvider).currentUser;
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(adminAuthServiceProvider).authStateChanges;
});

final isSuperAdminProvider = FutureProvider<bool>((ref) async {
  final authAsync = ref.watch(authStateProvider);
  return authAsync.when(
    loading: () async => true,
    error: (err, stack) => false,
    data: (user) async {
      if (user == null) return false;
      return ref.read(adminAuthServiceProvider).isCurrentUserSuperAdmin();
    },
  );
});
