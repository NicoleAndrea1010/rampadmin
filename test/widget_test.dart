import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rampadmin/core/config/demo_login_config.dart';
import 'package:rampadmin/core/theme/admin_theme.dart';
import 'package:rampadmin/core/widgets/admin_sidebar.dart';
import 'package:rampadmin/core/widgets/admin_top_bar.dart';
import 'package:rampadmin/features/auth/login_screen.dart';
import 'package:rampadmin/features/settings/settings_screen.dart';
import 'package:rampadmin/main.dart' show RampBootstrap;
import 'package:rampadmin/providers/auth_providers.dart';

void main() {
  testWidgets('Smoke test loads LoginScreen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: LoginScreen(onSuccess: () {})),
      ),
    );
    expect(find.textContaining('RAMP'), findsWidgets);
  });

  testWidgets('demo sign-in is absent when demo configuration is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoLoginConfigurationProvider.overrideWithValue(
            const DemoLoginConfiguration(
              enabled: false,
              email: '',
              password: '',
            ),
          ),
        ],
        child: MaterialApp(
          theme: AdminTheme.lightTheme,
          home: LoginScreen(onSuccess: () {}),
        ),
      ),
    );

    expect(find.text('Sign in as Demo Super Admin'), findsNothing);
  });

  testWidgets('demo sign-in passes configured credentials to admin auth', (
    tester,
  ) async {
    final demoConfig = DemoLoginConfiguration(
      enabled: true,
      email: 'demo.admin@example.test',
      password: 'test-only-${DateTime.now().microsecondsSinceEpoch}',
    );
    String? receivedEmail;
    String? receivedPassword;
    var succeeded = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoLoginConfigurationProvider.overrideWithValue(demoConfig),
          adminSignInCallbackProvider.overrideWithValue(({
            required email,
            required password,
          }) async {
            receivedEmail = email;
            receivedPassword = password;
          }),
        ],
        child: MaterialApp(
          theme: AdminTheme.lightTheme,
          home: LoginScreen(onSuccess: () => succeeded = true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in as Demo Super Admin'), findsOneWidget);
    await tester.tap(find.text('Sign in as Demo Super Admin'));
    await tester.pumpAndSettle();

    expect(receivedEmail, demoConfig.email);
    expect(receivedPassword, demoConfig.password);
    expect(find.text(demoConfig.password), findsNothing);
    expect(succeeded, isTrue);
  });

  testWidgets('demo authentication errors are mapped for the user', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoLoginConfigurationProvider.overrideWithValue(
            DemoLoginConfiguration(
              enabled: true,
              email: 'demo.admin@example.test',
              password: 'test-only-${DateTime.now().microsecondsSinceEpoch}',
            ),
          ),
          adminSignInCallbackProvider.overrideWithValue(({
            required email,
            required password,
          }) async {
            throw FirebaseAuthException(code: 'wrong-password');
          }),
        ],
        child: MaterialApp(
          theme: AdminTheme.lightTheme,
          home: LoginScreen(onSuccess: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in as Demo Super Admin'));
    await tester.pumpAndSettle();

    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(find.text('wrong-password'), findsNothing);
  });

  testWidgets(
    'settings fills available desktop width without profile or motion toggles',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AdminTheme.lightTheme,
            home: const Scaffold(body: SettingsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Guidance'), findsOneWidget);
      expect(find.text('Account'), findsNothing);
      expect(find.text('Open Profile'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      final cards = tester.widgetList<Card>(find.byType(Card));
      expect(cards.length, 2);
      expect(tester.getSize(find.byType(Card).first).width, greaterThan(500));
    },
  );

  testWidgets(
    'top avatar opens Profile directly and sidebar identity is static',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/settings',
        routes: [
          GoRoute(
            path: '/settings',
            builder: (context, state) => Scaffold(
              body: Column(
                children: [
                  const AdminTopBar(
                    title: 'Settings',
                    mobile: false,
                    onMenu: _emptyCallback,
                  ),
                  Expanded(
                    child: AdminSidebar(
                      currentRoute: '/settings',
                      onNavigate: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) =>
                const Scaffold(body: Text('Canonical Profile')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: AdminTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuButton<String>), findsNothing);
      await tester.tap(find.byTooltip('View administrator profile'));
      await tester.pumpAndSettle();
      expect(find.text('Canonical Profile'), findsOneWidget);
    },
  );

  testWidgets('startup splash waits for services without a fixed delay', (
    tester,
  ) async {
    final servicesReady = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        child: RampBootstrap(
          initializeServices: () => servicesReady.future,
          appBuilder: () =>
              const MaterialApp(home: Scaffold(body: Text('Workspace ready'))),
        ),
      ),
    );

    expect(find.text('RAMP'), findsOneWidget);
    expect(find.text('Preparing your workspace...'), findsOneWidget);
    servicesReady.complete();
    await tester.pumpAndSettle();
    expect(find.text('Workspace ready'), findsOneWidget);
  });

  testWidgets('startup initialization failure shows a retry screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: RampBootstrap(
          initializeServices: () async => throw StateError('private detail'),
          appBuilder: () =>
              const MaterialApp(home: Scaffold(body: Text('Workspace ready'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Workspace could not start'), findsOneWidget);
    expect(find.text('private detail'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  for (final size in [
    const Size(320, 700),
    const Size(390, 844),
    const Size(480, 844),
    const Size(768, 900),
    const Size(1024, 900),
    const Size(1280, 900),
    const Size(1440, 900),
  ]) {
    testWidgets('login layout fits ${size.width}px viewport', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            demoLoginConfigurationProvider.overrideWithValue(
              const DemoLoginConfiguration(
                enabled: false,
                email: '',
                password: '',
              ),
            ),
          ],
          child: MaterialApp(
            theme: AdminTheme.lightTheme,
            home: LoginScreen(onSuccess: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });
  }
}

void _emptyCallback() {}
