import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';

// =============================================================================
// SETTINGS SECTION
// =============================================================================

/// A card-style section container for settings items
class SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const SettingsSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: AppTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// =============================================================================
// SETTINGS TILE
// =============================================================================

/// A list tile for navigation/action settings
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  final bool destructive;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: destructive ? AppTheme.errorColor : AppTheme.textSecondary,
      ),
      title: Text(
        title,
        style: TextStyle(color: destructive ? AppTheme.errorColor : null),
      ),
      subtitle: Text(
        value,
        style: TextStyle(
          color: destructive
              ? AppTheme.errorColor.withValues(alpha: 0.7)
              : AppTheme.textMuted,
          fontSize: 13,
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: AppTheme.textMuted),
      onTap: onTap,
    );
  }
}

// =============================================================================
// SETTINGS SWITCH
// =============================================================================

/// A switch tile for toggle settings
class SettingsSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitch({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon, color: AppTheme.textSecondary),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
      ),
      value: value,
      activeThumbColor: AppTheme.primaryColor,
      onChanged: onChanged,
    );
  }
}

// =============================================================================
// PROVIDER TILE
// =============================================================================

/// A tile for content provider toggle
class ProviderTile extends StatelessWidget {
  final String name;
  final String url;
  final String? iconUrl;
  final bool isEnabled;
  final ValueChanged<bool> onChanged;

  const ProviderTile({
    super.key,
    required this.name,
    required this.url,
    this.iconUrl,
    required this.isEnabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isEnabled
              ? AppTheme.primaryColor.withValues(alpha: 0.15)
              : AppTheme.textMuted.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: iconUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: iconUrl!,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Icon(
                    Icons.movie_filter,
                    color: isEnabled
                        ? AppTheme.primaryColor
                        : AppTheme.textMuted,
                  ),
                ),
              )
            : Icon(
                Icons.movie_filter,
                color: isEnabled ? AppTheme.primaryColor : AppTheme.textMuted,
              ),
      ),
      title: Text(name),
      subtitle: Text(
        url,
        style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
      ),
      value: isEnabled,
      activeThumbColor: AppTheme.primaryColor,
      onChanged: onChanged,
    );
  }
}

// =============================================================================
// EMPTY PROVIDERS
// =============================================================================

/// Placeholder when no providers are registered
class EmptyProviders extends StatelessWidget {
  const EmptyProviders({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Немає провайдерів'),
                Text(
                  'Додайте джерела контенту',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SELECTION SHEET
// =============================================================================

/// A bottom sheet for selecting from a list of options
class SelectionSheet<T> extends StatelessWidget {
  final String title;
  final List<T> items;
  final T selectedItem;
  final Widget Function(T item) itemBuilder;
  final ValueChanged<T> onSelected;

  const SelectionSheet({
    super.key,
    required this.title,
    required this.items,
    required this.selectedItem,
    required this.itemBuilder,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textMuted.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          // Items
          ...items.map(
            (item) => InkWell(
              onTap: () => onSelected(item),
              child: itemBuilder(item),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// =============================================================================
// SELECTION ITEM
// =============================================================================

/// An item in a selection sheet
class SelectionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isSelected;

  const SelectionItem({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.15)
              : AppTheme.textMuted.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppTheme.primaryColor : null,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(color: AppTheme.textMuted))
          : null,
      trailing: isSelected
          ? Icon(Icons.check_circle, color: AppTheme.primaryColor)
          : null,
    );
  }
}
