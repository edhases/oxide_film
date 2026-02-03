import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/logger.dart';

/// Authentication service using Supabase Auth
class AuthService extends ChangeNotifier {
  static const _tag = 'AuthService';

  final _supabase = Supabase.instance.client;

  // Cached profile data
  Map<String, dynamic>? _profile;
  bool _isLoading = false;
  String? _error;

  // Getters
  User? get currentUser => _supabase.auth.currentUser;
  String? get userId => currentUser?.id;
  String? get userEmail => currentUser?.email;
  bool get isAuthenticated => currentUser != null;
  Map<String, dynamic>? get profile => _profile;
  bool get isLoading => _isLoading;
  String? get error => _error;

  String get displayName {
    if (_profile != null && _profile!['display_name'] != null) {
      return _profile!['display_name'];
    }
    return currentUser?.email?.split('@').first ?? 'Гість';
  }

  String? get avatarUrl => _profile?['avatar_url'];

  AuthService() {
    // Listen to auth state changes
    _supabase.auth.onAuthStateChange.listen((data) {
      Logger.d('Auth state changed: ${data.event}', tag: _tag);
      if (data.event == AuthChangeEvent.signedIn) {
        _loadProfile();
      } else if (data.event == AuthChangeEvent.signedOut) {
        _profile = null;
      }
      notifyListeners();
    });

    // Load profile if already authenticated
    if (isAuthenticated) {
      _loadProfile();
    }
  }

  /// Sign up with email and password
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    Logger.i('Attempting sign up for: $email', tag: _tag);
    _setLoading(true);
    _error = null;

    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName ?? email.split('@').first},
      );

      if (response.user == null) {
        throw Exception('Помилка реєстрації: користувач не створений');
      }

      Logger.i('Sign up successful for: ${response.user!.email}', tag: _tag);

      // Check if email confirmation is required
      if (response.user!.emailConfirmedAt == null) {
        Logger.d('Email confirmation required', tag: _tag);
      }

      await _loadProfile();
    } on AuthException catch (e) {
      Logger.e('Sign up failed', tag: _tag, error: e);
      _error = _translateAuthError(e.message);
      rethrow;
    } catch (e) {
      Logger.e('Sign up failed', tag: _tag, error: e);
      _error = e.toString();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Sign in with email and password
  Future<void> signIn({required String email, required String password}) async {
    Logger.i('Attempting sign in for: $email', tag: _tag);
    _setLoading(true);
    _error = null;

    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw Exception('Помилка входу');
      }

      Logger.i('Sign in successful for: ${response.user!.email}', tag: _tag);
      await _loadProfile();
    } on AuthException catch (e) {
      Logger.e('Sign in failed', tag: _tag, error: e);
      _error = _translateAuthError(e.message);
      rethrow;
    } catch (e) {
      Logger.e('Sign in failed', tag: _tag, error: e);
      _error = e.toString();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Sign out
  Future<void> signOut() async {
    Logger.i('Signing out user: $userEmail', tag: _tag);
    try {
      await _supabase.auth.signOut();
      _profile = null;
      notifyListeners();
      Logger.i('Sign out successful', tag: _tag);
    } catch (e) {
      Logger.e('Sign out failed', tag: _tag, error: e);
      rethrow;
    }
  }

  /// Reset password
  Future<void> resetPassword(String email) async {
    Logger.i('Requesting password reset for: $email', tag: _tag);
    _setLoading(true);
    _error = null;

    try {
      await _supabase.auth.resetPasswordForEmail(email);
      Logger.i('Password reset email sent to: $email', tag: _tag);
    } on AuthException catch (e) {
      Logger.e('Password reset failed', tag: _tag, error: e);
      _error = _translateAuthError(e.message);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Load user profile from database
  Future<void> _loadProfile() async {
    if (!isAuthenticated) {
      Logger.d('Cannot load profile: not authenticated', tag: _tag);
      return;
    }

    Logger.d('Loading profile for: $userId', tag: _tag);

    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId!)
          .maybeSingle();

      if (response != null) {
        _profile = response;
        Logger.d('Profile loaded: ${_profile!['display_name']}', tag: _tag);
      } else {
        Logger.w('Profile not found for user: $userId', tag: _tag);
        // Profile might not exist yet (trigger didn't fire)
        // Create it manually
        await _createProfileIfMissing();
      }
      notifyListeners();
    } catch (e) {
      Logger.e('Failed to load profile', tag: _tag, error: e);
    }
  }

  /// Create profile if it doesn't exist
  Future<void> _createProfileIfMissing() async {
    if (!isAuthenticated) return;

    Logger.d('Creating missing profile for: $userId', tag: _tag);

    try {
      await _supabase.from('profiles').upsert({
        'id': userId,
        'email': userEmail,
        'display_name': userEmail?.split('@').first ?? 'User',
      });

      // Reload profile
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId!)
          .single();

      _profile = response;
      Logger.i('Profile created successfully', tag: _tag);
      notifyListeners();
    } catch (e) {
      Logger.e('Failed to create profile', tag: _tag, error: e);
    }
  }

  /// Update user profile
  Future<void> updateProfile({
    String? displayName,
    String? avatarUrl,
    String? bio,
  }) async {
    if (!isAuthenticated) return;

    Logger.d('Updating profile for: $userId', tag: _tag);
    _setLoading(true);

    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (displayName != null) updates['display_name'] = displayName;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
      if (bio != null) updates['bio'] = bio;

      await _supabase.from('profiles').update(updates).eq('id', userId!);

      // Update local cache
      _profile = {...?_profile, ...updates};
      Logger.i('Profile updated successfully', tag: _tag);
      notifyListeners();
    } catch (e) {
      Logger.e('Failed to update profile', tag: _tag, error: e);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ============================================================================
  // WATCH HISTORY (Cloud Sync)
  // ============================================================================

  /// Save watch progress to cloud
  Future<void> saveWatchProgress({
    required String mediaId,
    required String providerId,
    required int positionMs,
    required int durationMs,
  }) async {
    if (!isAuthenticated) {
      Logger.d('Skipping cloud save: not authenticated', tag: _tag);
      return;
    }

    try {
      await _supabase.from('watch_history').upsert({
        'user_id': userId,
        'media_id': mediaId,
        'provider_id': providerId,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'last_watched': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,media_id,provider_id');

      Logger.d('Watch progress saved: $mediaId @ $positionMs ms', tag: _tag);
    } catch (e) {
      Logger.e('Failed to save watch progress to cloud', tag: _tag, error: e);
    }
  }

  /// Get watch history from cloud
  Future<List<Map<String, dynamic>>> getCloudWatchHistory({
    int limit = 50,
  }) async {
    if (!isAuthenticated) return [];

    try {
      final response = await _supabase
          .from('watch_history')
          .select()
          .eq('user_id', userId!)
          .order('last_watched', ascending: false)
          .limit(limit);

      Logger.d('Loaded ${response.length} history items from cloud', tag: _tag);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      Logger.e('Failed to load cloud watch history', tag: _tag, error: e);
      return [];
    }
  }

  /// Get watch position for specific media
  Future<int?> getWatchPosition(String mediaId, String providerId) async {
    if (!isAuthenticated) return null;

    try {
      final response = await _supabase
          .from('watch_history')
          .select('position_ms')
          .eq('user_id', userId!)
          .eq('media_id', mediaId)
          .eq('provider_id', providerId)
          .maybeSingle();

      return response?['position_ms'] as int?;
    } catch (e) {
      Logger.e('Failed to get watch position', tag: _tag, error: e);
      return null;
    }
  }

  // ============================================================================
  // FAVORITES (Cloud Sync)
  // ============================================================================

  /// Add to cloud favorites
  Future<void> addToCloudFavorites({
    required String mediaId,
    required String providerId,
  }) async {
    if (!isAuthenticated) return;

    try {
      await _supabase.from('favorites').upsert({
        'user_id': userId,
        'media_id': mediaId,
        'provider_id': providerId,
        'added_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,media_id,provider_id');

      Logger.d('Added to cloud favorites: $mediaId', tag: _tag);
    } catch (e) {
      Logger.e('Failed to add to cloud favorites', tag: _tag, error: e);
    }
  }

  /// Remove from cloud favorites
  Future<void> removeFromCloudFavorites({
    required String mediaId,
    required String providerId,
  }) async {
    if (!isAuthenticated) return;

    try {
      await _supabase
          .from('favorites')
          .delete()
          .eq('user_id', userId!)
          .eq('media_id', mediaId)
          .eq('provider_id', providerId);

      Logger.d('Removed from cloud favorites: $mediaId', tag: _tag);
    } catch (e) {
      Logger.e('Failed to remove from cloud favorites', tag: _tag, error: e);
    }
  }

  /// Get cloud favorites
  Future<List<Map<String, dynamic>>> getCloudFavorites() async {
    if (!isAuthenticated) return [];

    try {
      final response = await _supabase
          .from('favorites')
          .select()
          .eq('user_id', userId!)
          .order('added_at', ascending: false);

      Logger.d('Loaded ${response.length} favorites from cloud', tag: _tag);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      Logger.e('Failed to load cloud favorites', tag: _tag, error: e);
      return [];
    }
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  String _translateAuthError(String message) {
    // Translate common Supabase auth errors to Ukrainian
    if (message.contains('Invalid login credentials')) {
      return 'Невірний email або пароль';
    }
    if (message.contains('Email not confirmed')) {
      return 'Email не підтверджено. Перевірте пошту';
    }
    if (message.contains('User already registered')) {
      return 'Користувач з таким email вже існує';
    }
    if (message.contains('Password should be at least')) {
      return 'Пароль має бути щонайменше 6 символів';
    }
    if (message.contains('Invalid email')) {
      return 'Невірний формат email';
    }
    if (message.contains('rate limit')) {
      return 'Забагато спроб. Спробуйте пізніше';
    }
    return message;
  }

  /// Auth state stream for listening to changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
}
