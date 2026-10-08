import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static Future<void> initialize() async {
    if (!isConfigured) {
      throw StateError(
        'Supabase configuration is missing. Provide '
        '--dart-define=SUPABASE_URL=<project-url> and '
        '--dart-define=SUPABASE_ANON_KEY=<publishable-or-anon-key>.',
      );
    }
    // Keep compatibility with the requested supabase_flutter ^2.8.3 range.
    // ignore: deprecated_member_use
    await Supabase.initialize(url: url, anonKey: anonKey);
  }
}
