import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

abstract final class FirebaseErrorMapper {
  static String message(Object error) {
    final code = switch (error) {
      FirebaseAuthException e => e.code,
      FirebaseFunctionsException e => e.code,
      FirebaseException e => e.code,
      _ => '',
    };
    return switch (code) {
      'wrong-password' ||
      'invalid-credential' ||
      'user-not-found' => 'Email or password is incorrect.',
      'user-disabled' => 'This account has been disabled.',
      'permission-denied' =>
        'You do not have permission to view this information.',
      'already-exists' ||
      'email-already-in-use' => 'An account with this email already exists.',
      'unavailable' || 'network-request-failed' =>
        'Check your internet connection and try again.',
      'unauthenticated' => 'Your session has expired. Please sign in again.',
      'invalid-argument' => 'Please review the information and try again.',
      'failed-precondition' => 'The account status does not allow this action.',
      'resource-exhausted' =>
        'Too many administrator actions. Wait a minute and try again.',
      _ => 'Something went wrong. Please try again.',
    };
  }
}
