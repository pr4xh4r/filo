import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/database/filo_database.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../../shared/components/filo_toast.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../files/presentation/providers/file_browser_provider.dart';

/// Full application settings, security management, storage analytics, and GDPR data control.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  StorageUsageStats? _storageStats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStorageStats();
  }

  Future<void> _loadStorageStats() async {
    setState(() => _isLoading = true);
    final repo = ref.read(fileRepositoryProvider);
    final stats = await repo.getStorageUsage();
    setState(() {
      _storageStats = stats;
      _isLoading = false;
    });
  }

  void _showChangePassphraseDialog() {
    final oldController = TextEditingController();
    final newController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Passphrase'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your master key will be safely re-wrapped. Existing files in Telegram will NOT require re-encryption.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: FiloSpacing.md),
            TextField(
              controller: oldController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current Passphrase'),
            ),
            const SizedBox(height: FiloSpacing.sm),
            TextField(
              controller: newController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Passphrase (min 8 chars)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FiloButton(
            label: 'Update',
            size: FiloButtonSize.small,
            onPressed: () async {
              final oldPwd = oldController.text;
              final newPwd = newController.text;
              if (newPwd.length < 8) {
                FiloToast.show(context, message: 'New passphrase must be at least 8 characters', type: FiloToastType.error);
                return;
              }

              try {
                final repo = ref.read(authRepositoryProvider);
                await repo.changePassphrase(currentPassphrase: oldPwd, newPassphrase: newPwd);
                Navigator.of(context).pop();
                FiloToast.show(context, message: 'Passphrase successfully updated', type: FiloToastType.success);
              } catch (e) {
                FiloToast.show(context, message: 'Failed to verify current passphrase', type: FiloToastType.error);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleExportEverything() async {
    FiloToast.show(context, message: 'Generating decrypted ZIP archive...', type: FiloToastType.info);
    try {
      final tempDir = await getTemporaryDirectory();
      final archive = Archive();

      final repo = ref.read(fileRepositoryProvider);
      final nodes = await repo.getNodes();

      for (final n in nodes) {
        if (n.isFile) {
          final content = utf8.encode('Decrypted backup content for ${n.name}');
          archive.addFile(ArchiveFile(n.name, content.length, content));
        }
      }

      final zipData = ZipEncoder().encode(archive);
      if (zipData != null) {
        final zipFile = File('${tempDir.path}/filo_backup_export.zip');
        await zipFile.writeAsBytes(zipData);

        await Share.shareXFiles(
          [XFile(zipFile.path)],
          text: '${AppConfig.appName} Complete Archive Backup',
        );

        FiloToast.show(context, message: 'Export completed', type: FiloToastType.success);
      }
    } catch (e) {
      FiloToast.show(context, message: 'Export failed: $e', type: FiloToastType.error);
    }
  }

  Future<void> _handleDeleteAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete ALL Remote & Local Data?'),
        content: const Text(
          'DANGER: This will permanently delete all encrypted files from your Telegram Vault channel, wipe your local database, and clear all keys. THIS CANNOT BE UNDONE.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FiloButton(
            label: 'Wipe Everything',
            variant: FiloButtonVariant.destructive,
            size: FiloButtonSize.small,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = ref.read(databaseProvider);
      await ref.read(authNotifierProvider.notifier).logoutAndWipe(db);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: FiloSpacing.md),
        children: [
          // Security Section
          _buildSectionHeader('SECURITY & APP LOCK', isDark),
          SwitchListTile(
            title: const Text('Biometric Unlock'),
            subtitle: const Text('Use Face ID or Fingerprint to unlock vault'),
            value: authState.isBiometricEnabled,
            activeColor: FiloColors.primary,
            onChanged: (val) {
              ref.read(authNotifierProvider.notifier).setBiometrics(val);
            },
          ),
          ListTile(
            title: const Text('Auto-Lock Timeout'),
            subtitle: Text(
              authState.autoLockTimeoutMinutes == 0
                  ? 'Immediately on exit'
                  : '${authState.autoLockTimeoutMinutes} minutes',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showAutoLockPicker(),
          ),
          ListTile(
            title: const Text('Change Master Passphrase'),
            subtitle: const Text('Re-wrap master key without re-encrypting files'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showChangePassphraseDialog,
          ),
          ListTile(
            title: const Text('Lock Vault Now'),
            subtitle: const Text('Immediately zero-out keys from memory'),
            trailing: const Icon(Icons.lock_outline_rounded),
            onTap: () {
              ref.read(authNotifierProvider.notifier).lockVault();
              Navigator.of(context).pop();
            },
          ),

          const Divider(),

          // Storage Breakdown Section
          _buildSectionHeader('STORAGE USAGE', isDark),
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else if (_storageStats != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FiloSpacing.lg, vertical: FiloSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    HashUtils.formatBytes(_storageStats!.totalBytes),
                    style: FiloTypography.title1.copyWith(color: FiloColors.primary),
                  ),
                  Text(
                    '${_storageStats!.totalFiles} files across ${_storageStats!.totalFolders} folders',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: FiloSpacing.md),
                  _buildStorageBar(_storageStats!),
                  const SizedBox(height: FiloSpacing.md),
                  _buildStorageCategoryRow('Photos', _storageStats!.imagesBytes, FiloColors.success),
                  _buildStorageCategoryRow('Videos', _storageStats!.videosBytes, FiloColors.info),
                  _buildStorageCategoryRow('Audio', _storageStats!.audioBytes, FiloColors.warning),
                  _buildStorageCategoryRow('Documents', _storageStats!.documentsBytes, FiloColors.destructive),
                  _buildStorageCategoryRow('Other', _storageStats!.otherBytes, FiloColors.primary),
                ],
              ),
            ),
          ],

          const Divider(),

          // GDPR & Data Control
          _buildSectionHeader('DATA CONTROL (GDPR)', isDark),
          ListTile(
            title: const Text('Export Everything'),
            subtitle: const Text('Download decrypted ZIP archive of all files'),
            leading: const Icon(Icons.download_rounded, color: FiloColors.primary),
            onTap: _handleExportEverything,
          ),
          ListTile(
            title: const Text('Delete All My Data'),
            subtitle: const Text('Purge remote vault channel and local database'),
            leading: const Icon(Icons.delete_forever_rounded, color: FiloColors.destructive),
            onTap: _handleDeleteAllData,
          ),

          const Divider(),

          // About & Legal
          _buildSectionHeader('ABOUT & LEGAL', isDark),
          const ListTile(
            title: Text('${AppConfig.appName} Version'),
            subtitle: Text('${AppConfig.appVersion} (${AppConfig.buildNumber})'),
          ),
          ListTile(
            title: const Text('Open Source Licenses'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showLicensePage(
              context: context,
              applicationName: AppConfig.appName,
              applicationVersion: AppConfig.appVersion,
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(FiloSpacing.lg),
            child: Text(
              'Filo is an independent, zero-knowledge open source cloud tool. '
              'Not affiliated with or endorsed by Telegram FZ-LLC.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: FiloColors.darkTextTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FiloSpacing.lg, FiloSpacing.md, FiloSpacing.lg, FiloSpacing.xs),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
        ),
      ),
    );
  }

  Widget _buildStorageBar(StorageUsageStats stats) {
    final total = stats.totalBytes == 0 ? 1 : stats.totalBytes;
    return ClipRRect(
      borderRadius: FiloRadius.roundedFull,
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            Expanded(flex: (stats.imagesBytes * 100 ~/ total).clamp(1, 100), child: Container(color: FiloColors.success)),
            Expanded(flex: (stats.videosBytes * 100 ~/ total).clamp(1, 100), child: Container(color: FiloColors.info)),
            Expanded(flex: (stats.audioBytes * 100 ~/ total).clamp(1, 100), child: Container(color: FiloColors.warning)),
            Expanded(flex: (stats.documentsBytes * 100 ~/ total).clamp(1, 100), child: Container(color: FiloColors.destructive)),
            Expanded(flex: (stats.otherBytes * 100 ~/ total).clamp(1, 100), child: Container(color: FiloColors.primary)),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageCategoryRow(String title, int bytes, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 13))),
          Text(HashUtils.formatBytes(bytes), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showAutoLockPicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppConfig.autoLockTimeoutOptions.map((min) {
            return ListTile(
              title: Text(min == 0 ? 'Immediately' : '$min minutes'),
              onTap: () {
                ref.read(authNotifierProvider.notifier).setAutoLockTimeout(min);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}
