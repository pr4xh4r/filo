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
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../shared/components/diamond_pattern_painter.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../../shared/components/filo_toast.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../files/presentation/providers/file_browser_provider.dart';

/// Application Settings & Account Details.
///
/// Designed to match Screen 3 of the reference design:
/// - `< Settings` with action dots `⋮`
/// - Available storage balance with `+100% ↗ 2.4%` pill
/// - 3 card pattern carousel with Dark / Light / System selector dots
/// - Squircle preference action tiles
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
        title: const Text('Change Master Passphrase'),
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

  void _showAutoLockPicker() {
    final currentTimeout = ref.read(authNotifierProvider).autoLockTimeoutMinutes;
    final options = [0, 1, 5, 15, 30];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: FiloSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Auto-Lock Timeout',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: FiloSpacing.sm),
              ...options.map(
                (mins) => ListTile(
                  title: Text(mins == 0 ? 'Immediately on exit' : '$mins minutes'),
                  trailing: mins == currentTimeout ? const Icon(Icons.check, color: FiloColors.primary) : null,
                  onTap: () {
                    ref.read(authNotifierProvider.notifier).setAutoLockTimeout(mins);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(isDarkProvider);
    final currentThemeMode = ref.watch(themeModeProvider);
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      backgroundColor: isDark ? FiloColors.darkBackground : FiloColors.lightBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Account Details',
          style: FiloTypography.title2.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.more_vert_rounded,
              color: isDark ? Colors.white : Colors.black,
            ),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: FiloSpacing.xl, vertical: FiloSpacing.sm),
        physics: const BouncingScrollPhysics(),
        children: [
          // 1. Available Storage Hero (Screen 3 style)
          Text(
            'Available Storage',
            style: FiloTypography.caption.copyWith(
              color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _isLoading
                    ? 'Loading...'
                    : (_storageStats != null && _storageStats!.totalBytes > 0
                        ? HashUtils.formatBytes(_storageStats!.totalBytes)
                        : 'Unlimited'),
                style: FiloTypography.title1.copyWith(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.0,
                  color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: FiloColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text(
                  '+100% ↗ 2.4%',
                  style: TextStyle(
                    fontFamily: FiloTypography.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: FiloColors.success,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: FiloSpacing.md),

          // 2. Card Pattern Carousel (Screen 3: 3 Visual Pattern Cards)
          SizedBox(
            height: 80,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildPatternCard(
                  label: 'Dark Mode',
                  mode: ThemeMode.dark,
                  currentMode: currentThemeMode,
                  gradient: FiloColors.heroGradientDark,
                  isDark: isDark,
                ),
                const SizedBox(width: 12),
                _buildPatternCard(
                  label: 'Light Mode',
                  mode: ThemeMode.light,
                  currentMode: currentThemeMode,
                  gradient: FiloColors.heroGradient,
                  isDark: isDark,
                  hasDiamondPattern: true,
                ),
                const SizedBox(width: 12),
                _buildPatternCard(
                  label: 'System',
                  mode: ThemeMode.system,
                  currentMode: currentThemeMode,
                  color: isDark ? FiloColors.darkSurfaceSecondary : Colors.white,
                  isDark: isDark,
                  hasDottedBorder: true,
                ),
              ],
            ),
          ),

          // Dots Selector
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildThemeDot(label: 'Dark', mode: ThemeMode.dark, currentMode: currentThemeMode),
              const SizedBox(width: 16),
              _buildThemeDot(label: 'Light', mode: ThemeMode.light, currentMode: currentThemeMode),
              const SizedBox(width: 16),
              _buildThemeDot(label: 'System', mode: ThemeMode.system, currentMode: currentThemeMode),
            ],
          ),

          const SizedBox(height: FiloSpacing.lg),

          // 3. Preferences Section (Screen 3 style transactions list)
          Text(
            'Security & Vault Preferences',
            style: FiloTypography.title3.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: FiloSpacing.sm),

          _buildSettingsTile(
            icon: Icons.fingerprint_rounded,
            iconColor: FiloColors.primary,
            title: 'Biometric Unlock',
            subtitle: 'Scan fingerprint or face to open vault',
            trailing: Switch(
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
            isDark: isDark,
          ),

          _buildSettingsTile(
            icon: Icons.timer_outlined,
            iconColor: FiloColors.info,
            title: 'Auto-Lock Timeout',
            subtitle: authState.autoLockTimeoutMinutes == 0
                ? 'Immediately on exit'
                : '${authState.autoLockTimeoutMinutes} minutes',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showAutoLockPicker,
            isDark: isDark,
          ),

          _buildSettingsTile(
            icon: Icons.key_rounded,
            iconColor: FiloColors.warning,
            title: 'Change Master Passphrase',
            subtitle: 'Re-wrap key without re-encrypting files',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showChangePassphraseDialog,
            isDark: isDark,
          ),

          _buildSettingsTile(
            icon: Icons.lock_outline_rounded,
            iconColor: FiloColors.destructive,
            title: 'Lock Vault Now',
            subtitle: 'Clear master keys from device memory',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              HapticFeedback.lightImpact();
              ref.read(authNotifierProvider.notifier).lockVault();
              Navigator.of(context).pop();
            },
            isDark: isDark,
          ),

          const SizedBox(height: FiloSpacing.md),

          Text(
            'Data & Storage Controls',
            style: FiloTypography.title3.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: FiloSpacing.sm),

          _buildSettingsTile(
            icon: Icons.download_rounded,
            iconColor: FiloColors.success,
            title: 'Export Everything',
            subtitle: 'Download decrypted ZIP archive of all files',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _handleExportEverything,
            isDark: isDark,
          ),

          _buildSettingsTile(
            icon: Icons.delete_forever_rounded,
            iconColor: FiloColors.destructive,
            title: 'Delete All My Data',
            subtitle: 'Purge remote vault and wipe local database',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _handleDeleteAllData,
            isDark: isDark,
            isDestructive: true,
          ),

          const SizedBox(height: FiloSpacing.lg),

          // Bottom Account Details Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? FiloColors.darkSurfaceSecondary : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filo Vault Account Details',
                      style: FiloTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                      ),
                    ),
                    Text(
                      'Zero-Knowledge Client',
                      style: FiloTypography.caption.copyWith(
                        color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                      ),
                    ),
                  ],
                ),
                Text(
                  'v${AppConfig.appVersion} ⌵',
                  style: FiloTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? FiloColors.accentOrchid : FiloColors.primary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: FiloSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildPatternCard({
    required String label,
    required ThemeMode mode,
    required ThemeMode currentMode,
    List<Color>? gradient,
    Color? color,
    bool hasDiamondPattern = false,
    bool hasDottedBorder = false,
    required bool isDark,
  }) {
    final isSelected = currentMode == mode;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        ref.read(themeModeProvider.notifier).setThemeMode(mode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 120,
        decoration: BoxDecoration(
          gradient: gradient != null
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                )
              : null,
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? FiloColors.accentOrchid
                : (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08)),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: FiloColors.accentOrchid.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: hasDiamondPattern
            ? DiamondPatternOverlay(
                borderRadius: BorderRadius.circular(16),
                opacity: 0.18,
                spacing: 16.0,
                diamondSize: 6.0,
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontFamily: FiloTypography.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: FiloTypography.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: gradient != null ? Colors.white : (isDark ? Colors.white : Colors.black),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildThemeDot({
    required String label,
    required ThemeMode mode,
    required ThemeMode currentMode,
  }) {
    final isSelected = currentMode == mode;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        ref.read(themeModeProvider.notifier).setThemeMode(mode);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: isSelected ? FiloColors.accentOrchid : Colors.grey.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: FiloTypography.fontFamily,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? FiloColors.accentOrchid : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    required bool isDark,
    bool isDestructive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? FiloColors.darkSurfaceSecondary : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: ListTile(
          onTap: onTap != null
              ? () {
                  HapticFeedback.selectionClick();
                  onTap();
                }
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontFamily: FiloTypography.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDestructive
                  ? FiloColors.destructive
                  : (isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary),
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontFamily: FiloTypography.fontFamily,
              fontSize: 12,
              color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
            ),
          ),
          trailing: trailing,
        ),
      ),
    );
  }
}
