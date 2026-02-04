import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'core/config/secrets.dart';
import 'core/di/injection.dart';
import 'core/utils/logger.dart';
import 'data/providers/provider_registry.dart';
import 'presentation/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase for Watch Party (realtime sync)
  try {
    await Supabase.initialize(
      url: Secrets.supabaseUrl,
      anonKey: Secrets.supabaseAnonKey,
    );
    Logger.d('Supabase initialized', tag: 'Main');
  } catch (e) {
    Logger.w('Supabase init failed: $e', tag: 'Main');
  }

  // Initialize MediaKit
  MediaKit.ensureInitialized();

  // Initialize dependency injection
  await configureDependencies();

  // Resolve provider URLs in background (detects domain changes)
  _resolveProviderUrls();

  // Desktop window configuration
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'Oxide Film',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const OxideFilmApp());
}

/// Resolve provider URLs in background
///
/// This detects domain changes (e.g., uaflix.net -> uafix.net)
/// by following HTTP redirects and caching results.
void _resolveProviderUrls() {
  try {
    final registry = getIt<ProviderRegistry>();
    // Run in background, don't block app startup
    registry
        .resolveProviderUrls()
        .then((_) {
          Logger.d('Provider URLs resolved', tag: 'Main');
        })
        .catchError((e) {
          Logger.w('URL resolution failed: $e', tag: 'Main');
        });
  } catch (e) {
    Logger.w('Failed to start URL resolution: $e', tag: 'Main');
  }
}
