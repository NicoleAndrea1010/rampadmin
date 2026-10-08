import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'app.dart';
import 'core/theme/admin_theme.dart';
import 'core/config/supabase_config.dart';
import 'core/widgets/loading_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: RampBootstrap()));
}

Future<void> _initializeRampServices() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.SESSION);
  }

  if (SupabaseConfig.isConfigured) {
    await SupabaseConfig.initialize();
  } else {
    debugPrint(
      'Supabase configuration is missing; operational repositories will report load errors.',
    );
  }
}

class RampBootstrap extends StatefulWidget {
  const RampBootstrap({
    super.key,
    this.initializeServices = _initializeRampServices,
    this.appBuilder = _rampAdminApp,
  });

  final Future<void> Function() initializeServices;
  final Widget Function() appBuilder;

  @override
  State<RampBootstrap> createState() => _RampBootstrapState();
}

class _RampBootstrapState extends State<RampBootstrap> {
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _failed = false;
      _ready = false;
    });
    try {
      await widget.initializeServices();
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      debugPrint('RAMP service startup failed (${error.runtimeType}).');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.appBuilder();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.lightTheme,
      home: Scaffold(
        body: _failed
            ? _StartupError(onRetry: _initialize)
            : const LoadingView(message: 'Preparing your workspace...'),
      ),
    );
  }
}

Widget _rampAdminApp() => const RampAdminApp();

class _StartupError extends StatelessWidget {
  const _StartupError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFFE56F60),
              size: 42,
            ),
            const SizedBox(height: 16),
            Text(
              'Workspace could not start',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'RAMP could not initialize its required services. Check your connection and try again.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    ),
  );
}
