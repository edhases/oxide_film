import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';

/// Service for PocketBase backend interaction
/// Handles authentication and provides access to PocketBase client
class PocketBaseService {
  static const _tag = 'PocketBaseService';
  static const _authKey = 'pb_auth';

  late final PocketBase pb;

  PocketBaseService(SharedPreferences prefs) {
    // AsyncAuthStore automatically persists auth token
    final store = AsyncAuthStore(
      save: (String data) async {
        await prefs.setString(_authKey, data);
        Logger.d('Auth token saved (prefs)', tag: _tag);
      },
      clear: () async {
        await prefs.remove(_authKey);
        Logger.d('Auth token cleared (prefs)', tag: _tag);
      },
    );

    // Initialize PocketBase client
    pb = PocketBase(AppConfig.backendUrl, authStore: store);

    // Load initial data
    final data = prefs.getString(_authKey);
    if (data != null) {
      pb.authStore.save(data, null); // Load into memory store
      if (isAuthenticated) {
        Logger.i('Found existing auth: $userEmail', tag: _tag);
      }
    }

    Logger.i('PocketBase initialized: ${AppConfig.backendUrl}', tag: _tag);
  }

  // Quick access properties
  bool get isAuthenticated => pb.authStore.isValid;
  String? get userId => pb.authStore.model?.id;
  String? get userEmail => pb.authStore.model?.getStringValue('email');
  String? get userName => pb.authStore.model?.getStringValue('name');

  /// Sign in with email and password
  Future<void> signIn(String email, String password) async {
    await pb.collection('users').authWithPassword(email, password);
    Logger.i('User signed in: $email', tag: _tag);
  }

  /// Create new account and sign in
  Future<void> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    // 1. Create user record
    await pb
        .collection('users')
        .create(
          body: {
            'email': email,
            'password': password,
            'passwordConfirm': password,
            'name': name,
          },
        );

    // 2. Automatically sign in
    await signIn(email, password);
    Logger.i('User signed up and logged in: $email', tag: _tag);
  }

  /// Sign out and clear auth
  Future<void> signOut() async {
    final email = userEmail;
    pb.authStore.clear();
    Logger.i('User signed out: $email', tag: _tag);
  }

  /// Refresh authentication token
  Future<bool> refreshAuth() async {
    if (!isAuthenticated) return false;

    try {
      await pb.collection('users').authRefresh();
      Logger.d('Auth token refreshed', tag: _tag);
      return true;
    } catch (e) {
      Logger.w('Failed to refresh auth: $e', tag: _tag);
      return false;
    }
  }

  /// Sign in with OAuth2 (Google, Discord, etc.)
  Future<void> authWithOAuth2(
    String provider,
    Future<void> Function(Uri url) urlLauncher,
  ) async {
    await pb.collection('users').authWithOAuth2(provider, (url) async {
      await urlLauncher(url);
    });
    Logger.i('OAuth2 operation successful for provider: $provider', tag: _tag);
  }

  /// List linked external auth providers for the current user
  Future<List<Map<String, dynamic>>> listExternalAuths() async {
    if (!isAuthenticated || userId == null) return [];
    try {
      // Manual API call because 0.19 SDK lacks listExternalAuths method
      final response = await pb.send(
        '/api/collections/users/records/$userId/external-auths',
        method: 'GET',
      );

      if (response is List) {
        return List<Map<String, dynamic>>.from(response);
      }
      Logger.d('External auths response: $response', tag: _tag);
      return [];
    } catch (e) {
      Logger.e('Failed to list external auths', tag: _tag, error: e);
      return [];
    }
  }

  /// Unlink an external auth provider
  Future<void> unlinkExternalAuth(String provider) async {
    if (!isAuthenticated || userId == null) return;
    try {
      // Manual API call because 0.19 SDK lacks unlinkExternalAuth method
      await pb.send(
        '/api/collections/users/records/$userId/external-auths/$provider',
        method: 'DELETE',
      );
      Logger.i('Unlinked provider: $provider', tag: _tag);
    } catch (e) {
      Logger.e('Failed to unlink provider: $provider', tag: _tag, error: e);
      rethrow;
    }
  }
}
