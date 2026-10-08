import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return web;
      case TargetPlatform.iOS:
        return web;
      case TargetPlatform.macOS:
        return web;
      case TargetPlatform.windows:
        return web;
      case TargetPlatform.linux:
        return web;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const String apiKeyEnv = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: "AIzaSyC0kBf8GfkO756xM8nQJx-CYlF7EVS6IWk",
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: apiKeyEnv,
    authDomain: "rampdb123.firebaseapp.com",
    projectId: "rampdb123",
    storageBucket: "rampdb123.firebasestorage.app",
    messagingSenderId: "744537744434",
    appId: "1:744537744434:web:1d24dd4108d92ff9fa882b",
  );
}
