import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Unified error display widget for consistent error UI across the app.
///
/// Features:
/// - Customizable icon, title, and message
/// - Optional retry button
/// - Optional back button
/// - Alternative actions (e.g., try different stream)
class AppErrorWidget extends StatelessWidget {
  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;
  final List<Widget>? alternativeActions;
  final IconData icon;
  final Color? iconColor;

  const AppErrorWidget({
    super.key,
    this.title,
    this.message,
    this.onRetry,
    this.onBack,
    this.alternativeActions,
    this.icon = Icons.error_outline,
    this.iconColor,
  });

  /// Creates an error widget for network/loading failures
  factory AppErrorWidget.loading({
    String? message,
    VoidCallback? onRetry,
    VoidCallback? onBack,
  }) {
    return AppErrorWidget(
      title: 'Помилка завантаження',
      message: message,
      onRetry: onRetry,
      onBack: onBack,
      icon: Icons.cloud_off,
    );
  }

  /// Creates an error widget for playback failures
  factory AppErrorWidget.playback({
    String? message,
    VoidCallback? onRetry,
    VoidCallback? onBack,
    List<Widget>? alternativeActions,
  }) {
    return AppErrorWidget(
      title: 'Помилка відтворення',
      message: message ?? 'Не вдалося завантажити відео',
      onRetry: onRetry,
      onBack: onBack,
      alternativeActions: alternativeActions,
      icon: Icons.videocam_off,
      iconColor: Colors.red,
    );
  }

  /// Creates a generic error widget
  factory AppErrorWidget.generic({String? message, VoidCallback? onRetry}) {
    return AppErrorWidget(
      title: 'Щось пішло не так',
      message: message,
      onRetry: onRetry,
      icon: Icons.warning_amber_rounded,
      iconColor: Colors.orange,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Icon(icon, size: 64, color: iconColor ?? AppTheme.errorColor),
            const SizedBox(height: 16),

            // Title
            if (title != null)
              Text(
                title!,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

            // Message
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],

            // Action buttons
            if (onRetry != null || onBack != null) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onRetry != null)
                    ElevatedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Спробувати знову'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  if (onRetry != null && onBack != null)
                    const SizedBox(width: 12),
                  if (onBack != null)
                    OutlinedButton.icon(
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Назад'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: const BorderSide(color: AppTheme.borderColor),
                      ),
                    ),
                ],
              ),
            ],

            // Alternative actions
            if (alternativeActions != null &&
                alternativeActions!.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Або спробуйте:',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: alternativeActions!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
