import 'package:flutter/foundation.dart';

class DemoLoginConfiguration {
  const DemoLoginConfiguration({
    required this.enabled,
    required this.email,
    required this.password,
  });

  factory DemoLoginConfiguration.fromEnvironment() =>
      const DemoLoginConfiguration(
        enabled: kDebugMode && bool.fromEnvironment('DEMO_ADMIN_ENABLED'),
        email: String.fromEnvironment('DEMO_ADMIN_EMAIL'),
        password: String.fromEnvironment('DEMO_ADMIN_PASSWORD'),
      );

  final bool enabled;
  final String email;
  final String password;

  bool get isAvailable =>
      enabled && email.trim().isNotEmpty && password.isNotEmpty;
}
