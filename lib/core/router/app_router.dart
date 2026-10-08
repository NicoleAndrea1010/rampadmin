import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/activity/admin_activity_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/landlords/landlord_details_screen.dart';
import '../../features/landlords/landlord_form_screen.dart';
import '../../features/landlords/landlord_list_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/not_found_screen.dart';
import '../../features/operations/operational_data_screen.dart';
import '../../providers/auth_providers.dart';
import '../constants/admin_routes.dart';
import '../widgets/admin_shell.dart';
import '../widgets/error_view.dart';
import '../widgets/loading_view.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefreshNotifier(FirebaseAuth.instance.idTokenChanges());
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: AdminRoutes.dashboard,
    refreshListenable: refresh,
    errorBuilder: (context, state) => const NotFoundScreen(),
    redirect: (context, state) {
      final signedIn = FirebaseAuth.instance.currentUser != null;
      final atLogin = state.matchedLocation == AdminRoutes.login;
      if (!signedIn && !atLogin) return AdminRoutes.login;
      return null;
    },
    routes: [
      GoRoute(
        path: AdminRoutes.login,
        builder: (context, state) =>
            LoginScreen(onSuccess: () => context.go(AdminRoutes.dashboard)),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            _ProtectedShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: AdminRoutes.dashboard,
            builder: (_, _) => const DashboardScreen(),
          ),
          GoRoute(
            path: AdminRoutes.landlords,
            builder: (_, _) => const LandlordListScreen(),
          ),
          GoRoute(
            path: AdminRoutes.operations,
            builder: (_, _) => const OperationalDataScreen(),
          ),
          GoRoute(
            path: AdminRoutes.landlordNew,
            builder: (_, _) => const LandlordFormScreen(),
          ),
          GoRoute(
            path: '/landlords/:uid/edit',
            builder: (_, state) =>
                LandlordFormScreen(landlordUid: state.pathParameters['uid']),
          ),
          GoRoute(
            path: AdminRoutes.landlordDetails,
            builder: (_, state) => LandlordDetailsScreen(
              landlordUid: state.pathParameters['uid']!,
            ),
          ),
          GoRoute(
            path: AdminRoutes.activity,
            builder: (_, _) => const AdminActivityScreen(),
          ),
          GoRoute(
            path: AdminRoutes.settings,
            builder: (_, _) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Stream<User?> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<User?> _subscription;
  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class _ProtectedShell extends ConsumerWidget {
  const _ProtectedShell({required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verification = ref.watch(isSuperAdminProvider);
    return verification.when(
      loading: () => const Scaffold(
        body: LoadingView(message: 'Verifying super-admin access...'),
      ),
      error: (_, _) => _AccessDenied(onSignOut: () => _signOut(context, ref)),
      data: (allowed) {
        if (!allowed) {
          return _AccessDenied(onSignOut: () => _signOut(context, ref));
        }
        return AdminShell(currentRoute: location, child: child);
      },
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(adminAuthServiceProvider).signOut();
    if (context.mounted) context.go(AdminRoutes.login);
  }
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied({required this.onSignOut});
  final VoidCallback onSignOut;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: ErrorView(
      message: 'This account does not have super-admin access.',
      onRetry: onSignOut,
      actionLabel: 'Return to sign in',
    ),
  );
}
