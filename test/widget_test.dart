import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rampadmin/features/auth/login_screen.dart';

void main() {
  testWidgets('Smoke test loads LoginScreen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: LoginScreen(onSuccess: () {})),
      ),
    );
    expect(find.textContaining('RAMP'), findsWidgets);
  });
}
