import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/database/chunk_model.dart';
import '../../../../core/database/filo_database.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_motion.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../../shared/components/filo_sheet.dart';
import '../../../../shared/components/filo_toast.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../files/presentation/providers/file_browser_provider.dart';

/// Full application settings, appearance management, security, storage analytics, and GDPR data control.
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
    if (mounted) {
      setState(() {
        _storageStats = stats;
        _isLoading = false;
      });
    }
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
                if (context.mounted) {
                  Navigator.of(context).pop();
                  FiloToast.show(context, message: 'Passphrase successfully updated', type: FiloToastType.success);
                }
              } catch (e) {
                if (context.mounted) {
                  FiloToast.show(context, message: 'Failed to verify current passphrase', type: FiloToastType.error);
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleExportEverything() async {
    final authState = ref.read(authNotifierProvider);
    final masterKey = authState.masterKey;
    if (masterKey == null) {
      FiloToast.show(context, message: 'Vault is locked. Unlock before exporting.', type: FiloToastType.error);
      return;
    }

    FiloToast.show(context, message: 'Decrypting files & generating ZIP archive...', type: FiloToastType.info);
    try {
      final tempDir = await getTemporaryDirectory();
      final archive = Archive();

      final repo = ref.read(fileRepositoryProvider);
      final storage = ref.read(storageBackendProvider);
      final channel = await storage.getOrCreateVaultChannel(AppConfig.vaultChannelTitle);
      final nodes = await repo.getNodes();
      final fileNodes = nodes.where((n) => n.isFile).toList();

      if (fileNodes.isEmpty) {
        if (mounted) {
          FiloToast.show(context, message: 'No files to export in vault', type: FiloToastType.warning);
        }
        return;
      }

      int exportedCount = 0;
      for (final n in fileNodes) {
        try {
          final chunks = await repo.getChunksForNode(n.id);
          Uint8List fileBytes;
          if (chunks.isNotEmpty) {
            final sortedChunks = List<FileChunk>.from(chunks)
              ..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
            final bytesBuilder = BytesBuilder();
            for (final c in sortedChunks) {
              final cipherBytes = await storage.downloadChunk(
                channelId: channel.channelId,
                remoteFileId: c.remoteFileId,
              );
              final decrypted = await CryptoEngine.decryptBytes(
                combinedBytes: cipherBytes,
                key: masterKey,
              );
              bytesBuilder.add(decrypted);
            }
            fileBytes = bytesBuilder.toBytes();
          } else {
            fileBytes = Uint8List(0);
          }

          String zipEntryName = n.name;
          if (n.parentId != null) {
            final crumbs = await repo.getBreadcrumbs(n.id);
            if (crumbs.length > 1) {
              final folderPath = crumbs.take(crumbs.length - 1).map((c) => c.name).join('/');
              zipEntryName = '$folderPath/${n.name}';
            }
          }

          archive.addFile(ArchiveFile(zipEntryName, fileBytes.length, fileBytes));
          exportedCount++;
        } catch (e) {
          debugPrint('Error decrypting file ${n.name}: $e');
        }
      }

      final zipData = ZipEncoder().encode(archive);
      if (zipData != null && zipData.isNotEmpty) {
        final zipFile = File('${tempDir.path}/filo_backup_export_${DateTime.now().millisecondsSinceEpoch}.zip');
        await zipFile.writeAsBytes(zipData, flush: true);

        await Share.shareXFiles(
          [XFile(zipFile.path, mimeType: 'application/zip', name: 'filo_backup_export.zip')],
          text: '${AppConfig.appName} Complete Archive Backup ($exportedCount files)',
        );

        if (mounted) {
          FiloToast.show(context, message: 'Exported $exportedCount files to ZIP', type: FiloToastType.success);
        }
      } else {
        throw Exception('ZIP compression failed');
      }
    } catch (e) {
      if (mounted) {
        FiloToast.show(context, message: 'Export failed: $e', type: FiloToastType.error);
      }
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
    final isDark = ref.watch(isDarkProvider);
    final currentThemeMode = ref.watch(themeModeProvider);
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: FiloSpacing.md),
        children: [
          // 1. Appearance Section
          _buildSectionHeader('APPEARANCE', isDark),
          _buildAppearanceSelector(currentThemeMode, isDark),
          const SizedBox(height: FiloSpacing.lg),

          // 2. Security Section
          _buildSectionHeader('SECURITY & VAULT LOCK', isDark),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FiloSpacing.lg),
            child: _buildGroupedCard(
              isDark: isDark,
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: FiloSpacing.md),
                  secondary: Container(
                    padding: const EdgeInsets.all(FiloSpacing.xs + 2),
                    decoration: BoxDecoration(
                      color: FiloColors.primary.withValues(alpha: 0.12),
                      borderRadius: FiloRadius.roundedMd,
                    ),
                    child: const Icon(Icons.fingerprint_rounded, color: FiloColors.primary, size: 22),
                  ),
                  title: const Text('Biometric Unlock', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  subtitle: const Text('Scan fingerprint or face to open vault', style: TextStyle(fontSize: 13)),
                  value: authState.isBiometricEnabled,
                  activeColor: FiloColors.primary,
                  onChanged: (val) async {
                    final success = await ref.read(authNotifierProvider.notifier).setBiometrics(val);
                    if (!success && mounted) {
                      final err = ref.read(authNotifierProvider).errorMessage;
                      if (err != null) {
                        FiloToast.show(context, message: err, type: FiloToastType.error);
                      }
                    } else if (success && mounted) {
                      FiloToast.show(
                        context,
                        message: val ? 'Biometric unlock enabled' : 'Biometric unlock disabled',
                        type: FiloToastType.info,
                      );
                    }
                  },
                ),
                _buildCardDivider(isDark),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: FiloSpacing.md),
                  leading: Container(
                    padding: const EdgeInsets.all(FiloSpacing.xs + 2),
                    decoration: BoxDecoration(
                      color: FiloColors.info.withValues(alpha: 0.12),
                      borderRadius: FiloRadius.roundedMd,
                    ),
                    child: const Icon(Icons.timer_outlined, color: FiloColors.info, size: 22),
                  ),
                  title: const Text('Auto-Lock Timeout', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  subtitle: Text(
                    authState.autoLockTimeoutMinutes == 0
                        ? 'Immediately on exit'
                        : '${authState.autoLockTimeoutMinutes} minutes',
                    style: const TextStyle(fontSize: 13),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showAutoLockPicker(),
                ),
                _buildCardDivider(isDark),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: FiloSpacing.md),
                  leading: Container(
                    padding: const EdgeInsets.all(FiloSpacing.xs + 2),
                    decoration: BoxDecoration(
                      color: FiloColors.warning.withValues(alpha: 0.12),
                      borderRadius: FiloRadius.roundedMd,
                    ),
                    child: const Icon(Icons.key_rounded, color: FiloColors.warning, size: 22),
                  ),
                  title: const Text('Change Master Passphrase', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  subtitle: const Text('Re-wrap key without re-encrypting files', style: TextStyle(fontSize: 13)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showChangePassphraseDialog,
                ),
                _buildCardDivider(isDark),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: FiloSpacing.md),
                  leading: Container(
                    padding: const EdgeInsets.all(FiloSpacing.xs + 2),
                    decoration: BoxDecoration(
                      color: FiloColors.destructive.withValues(alpha: 0.12),
                      borderRadius: FiloRadius.roundedMd,
                    ),
                    child: const Icon(Icons.lock_rounded, color: FiloColors.destructive, size: 22),
                  ),
                  title: const Text('Lock Vault Now', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  subtitle: const Text('Clear master keys from device memory', style: TextStyle(fontSize: 13)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref.read(authNotifierProvider.notifier).lockVault();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: FiloSpacing.lg),

          // 3. Storage Breakdown Section
          _buildSectionHeader('STORAGE USAGE', isDark),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FiloSpacing.lg),
            child: _buildGroupedCard(
              isDark: isDark,
              children: [
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(FiloSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_storageStats != null)
                  Padding(
                    padding: const EdgeInsets.all(FiloSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              HashUtils.formatBytes(_storageStats!.totalBytes),
                              style: FiloTypography.title1.copyWith(
                                color: FiloColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${_storageStats!.totalFiles} files',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: FiloSpacing.sm),
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
            ),
          ),
          const SizedBox(height: FiloSpacing.lg),

          // 4. GDPR & Data Control
          _buildSectionHeader('DATA CONTROL (GDPR)', isDark),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FiloSpacing.lg),
            child: _buildGroupedCard(
              isDark: isDark,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: FiloSpacing.md),
                  leading: Container(
                    padding: const EdgeInsets.all(FiloSpacing.xs + 2),
                    decoration: BoxDecoration(
                      color: FiloColors.primary.withValues(alpha: 0.12),
                      borderRadius: FiloRadius.roundedMd,
                    ),
                    child: const Icon(Icons.download_rounded, color: FiloColors.primary, size: 22),
                  ),
                  title: const Text('Export Everything', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  subtitle: const Text('Download decrypted ZIP archive of all files', style: TextStyle(fontSize: 13)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _handleExportEverything,
                ),
                _buildCardDivider(isDark),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: FiloSpacing.md),
                  leading: Container(
                    padding: const EdgeInsets.all(FiloSpacing.xs + 2),
                    decoration: BoxDecoration(
                      color: FiloColors.destructive.withValues(alpha: 0.12),
                      borderRadius: FiloRadius.roundedMd,
                    ),
                    child: const Icon(Icons.delete_forever_rounded, color: FiloColors.destructive, size: 22),
                  ),
                  title: const Text(
                    'Delete All My Data',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: FiloColors.destructive),
                  ),
                  subtitle: const Text('Purge remote vault and wipe local database', style: TextStyle(fontSize: 13)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _handleDeleteAllData,
                ),
              ],
            ),
          ),
          const SizedBox(height: FiloSpacing.lg),

          // 5. About & Legal
          _buildSectionHeader('ABOUT & LEGAL', isDark),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FiloSpacing.lg),
            child: _buildGroupedCard(
              isDark: isDark,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: FiloSpacing.md),
                  title: const Text('Filo Version', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  subtitle: const Text('${AppConfig.appVersion} (${AppConfig.buildNumber})', style: TextStyle(fontSize: 13)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: FiloColors.primary.withValues(alpha: 0.1),
                      borderRadius: FiloRadius.roundedFull,
                    ),
                    child: const Text('Zero-Knowledge', style: TextStyle(fontSize: 11, color: FiloColors.primary, fontWeight: FontWeight.w600)),
                  ),
                ),
                _buildCardDivider(isDark),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: FiloSpacing.md),
                  title: const Text('Open Source Licenses', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: AppConfig.appName,
                    applicationVersion: AppConfig.appVersion,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(FiloSpacing.xl),
            child: Text(
              '${AppConfig.appName} is an independent, zero-knowledge open source cloud vault.\n'
              'Not affiliated with or endorsed by Telegram FZ-LLC.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceSelector(ThemeMode currentMode, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FiloSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isDark ? FiloColors.darkSurface : FiloColors.lightSurface,
          borderRadius: FiloRadius.roundedLg,
          border: Border.all(
            color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            _buildThemeOption(
              label: 'System',
              icon: Icons.brightness_auto_rounded,
              mode: ThemeMode.system,
              currentMode: currentMode,
              isDark: isDark,
            ),
            _buildThemeOption(
              label: 'Light',
              icon: Icons.light_mode_rounded,
              mode: ThemeMode.light,
              currentMode: currentMode,
              isDark: isDark,
            ),
            _buildThemeOption(
              label: 'Dark',
              icon: Icons.dark_mode_rounded,
              mode: ThemeMode.dark,
              currentMode: currentMode,
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption({
    required String label,
    required IconData icon,
    required ThemeMode mode,
    required ThemeMode currentMode,
    required bool isDark,
  }) {
    final isSelected = currentMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (!isSelected) {
            HapticFeedback.selectionClick();
            ref.read(themeModeProvider.notifier).setThemeMode(mode);
          }
        },
        child: AnimatedContainer(
          duration: FiloMotion.durationFast,
          curve: FiloMotion.easeOut,
          padding: const EdgeInsets.symmetric(vertical: FiloSpacing.sm + 4),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? FiloColors.darkSurfaceSecondary : FiloColors.lightSurfaceSecondary)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(FiloRadius.md),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected
                    ? FiloColors.primary
                    : (isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? (isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary)
                      : (isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupedCard({
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? FiloColors.darkSurface : FiloColors.lightSurface,
        borderRadius: FiloRadius.roundedLg,
        border: Border.all(
          color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: FiloRadius.roundedLg,
        child: Column(
          children: children,
        ),
      ),
    );
  }

  Widget _buildCardDivider(bool isDark) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: FiloSpacing.md,
      color: isDark ? FiloColors.darkBorderSubtle : FiloColors.lightBorderSubtle,
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FiloSpacing.lg, FiloSpacing.sm, FiloSpacing.lg, FiloSpacing.xs),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
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
        height: 10,
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
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
          Text(HashUtils.formatBytes(bytes), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showAutoLockPicker() {
    FiloSheet.show(
      context: context,
      title: 'Auto-Lock Timeout',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: AppConfig.autoLockTimeoutOptions.map((min) {
          return ListTile(
            title: Text(min == 0 ? 'Immediately on exit' : '$min minutes'),
            trailing: ref.read(authNotifierProvider).autoLockTimeoutMinutes == min
                ? const Icon(Icons.check_rounded, color: FiloColors.primary)
                : null,
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(authNotifierProvider.notifier).setAutoLockTimeout(min);
              Navigator.of(context).pop();
            },
          );
        }).toList(),
      ),
    );
  }
}
