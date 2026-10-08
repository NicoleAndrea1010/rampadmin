import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/admin_auth_service.dart';
import '../core/config/demo_login_config.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final adminAuthServiceProvider = Provider<AdminAuthService>((ref) {
  return AdminAuthService(ref.watch(firebaseAuthProvider));
});

typedef AdminSignInCallback = Future<void> Function({
  required String email,
  required String password,
});

final adminSignInCallbackProvider = Provider<AdminSignInCallback>((ref) {
  final authService = ref.watch(adminAuthServiceProvider);
  return ({required email, required password}) async {
    await authService.signIn(email: email, password: password);
  };
});

final demoLoginConfigurationProvider = Provider<DemoLoginConfiguration>(
  (ref) => DemoLoginConfiguration.fromEnvironment(),
);

class LoginTransitionNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setInProgress(bool value) => state = value;
}

final loginTransitionProvider = NotifierProvider<LoginTransitionNotifier, bool>(
  LoginTransitionNotifier.new,
);

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
    loading: () async => false,
    error: (err, stack) => false,
    data: (user) async {
      if (user == null) return false;
      return ref.read(adminAuthServiceProvider).isCurrentUserSuperAdmin();
    },
  );
});
