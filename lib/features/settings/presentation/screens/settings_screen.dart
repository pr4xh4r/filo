import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
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
import '../../../../shared/components/filo_background.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../../shared/components/filo_glass.dart';
import '../../../../shared/components/filo_qr_card.dart';
import '../../../../shared/components/filo_toast.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../files/presentation/providers/file_browser_provider.dart';

/// Application Settings & Account Details (Pure Light Theme).
///
/// Designed with Apple-level precision:
/// - `< settings` handwritten header
/// - Available storage balance with status indicator pill
/// - Zero-knowledge cloud vault info card
/// - Tactile squircle preference action tiles
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Change Master Passphrase'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your master key will be safely re-wrapped. Existing files in Telegram will NOT require re-encryption.',
              style: TextStyle(fontSize: 13, color: FiloColors.lightTextSecondary),
            ),
            const SizedBox(height: FiloSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E5EA)),
              ),
              child: TextField(
                controller: oldController,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: 'Current Passphrase',
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: FiloSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E5EA)),
              ),
              child: TextField(
                controller: newController,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: 'New Passphrase (min 8 chars)',
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
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
                FiloToast.show(
                  context,
                  message: 'New passphrase must be at least 8 characters',
                  type: FiloToastType.error,
                );
                return;
              }

              try {
                final repo = ref.read(authRepositoryProvider);
                await repo.changePassphrase(currentPassphrase: oldPwd, newPassphrase: newPwd);
                if (context.mounted) {
                  Navigator.of(context).pop();
                  FiloToast.show(
                    context,
                    message: 'Passphrase successfully updated',
                    type: FiloToastType.success,
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  FiloToast.show(
                    context,
                    message: 'Failed to verify current passphrase',
                    type: FiloToastType.error,
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showQrPairingModal() async {
    final repo = ref.read(authRepositoryProvider);
    final bundle = await repo.exportVaultKeyBundle();
    final jsonStr = json.encode(bundle);
    final b64 = base64Url.encode(utf8.encode(jsonStr));
    final pairingPayload = 'filo://vault?bundle=$b64';

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        child: FiloQrCard(
          title: 'pair new device',
          subtitle: 'scan this qr code from another phone running filo to seamlessly unlock your vault.',
          data: pairingPayload,
        ),
      ),
    );
  }

  Future<void> _handleExportEverything() async {
    final authState = ref.read(authNotifierProvider);
    final masterKey = authState.masterKey;
    if (masterKey == null) {
      FiloToast.show(
        context,
        message: 'Vault is locked. Unlock before exporting.',
        type: FiloToastType.error,
      );
      return;
    }

    FiloToast.show(
      context,
      message: 'Decrypting files & generating ZIP archive...',
      type: FiloToastType.info,
    );
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
          FiloToast.show(
            context,
            message: 'No files to export in vault',
            type: FiloToastType.warning,
          );
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
        final zipFile = File(
          '${tempDir.path}/filo_backup_export_${DateTime.now().millisecondsSinceEpoch}.zip',
        );
        await zipFile.writeAsBytes(zipData, flush: true);

        await Share.shareXFiles(
          [XFile(zipFile.path, mimeType: 'application/zip', name: 'filo_backup_export.zip')],
          text: '${AppConfig.appName} Complete Archive Backup ($exportedCount files)',
        );

        if (mounted) {
          FiloToast.show(
            context,
            message: 'Exported $exportedCount files to ZIP',
            type: FiloToastType.success,
          );
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
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFF9F7),
                    Color(0xFFFBF4FF),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: FiloColors.destructive.withValues(alpha: 0.1),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Warning Shield Icon with glowing ring
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: FiloColors.destructive.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: FiloColors.destructive.withValues(alpha: 0.25),
                        width: 2,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.delete_forever_rounded,
                        color: FiloColors.destructive,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Title
                  Text(
                    'Wipe All Vault Data?',
                    textAlign: TextAlign.center,
                    style: FiloTypography.title2.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      letterSpacing: -0.5,
                      color: FiloColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Warning Explanation Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: FiloColors.destructive.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: FiloColors.destructive,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'This will permanently delete all encrypted files from your Telegram Vault channel, wipe your local database, and clear all keys.',
                                style: FiloTypography.caption.copyWith(
                                  color: FiloColors.lightTextSecondary,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'THIS CANNOT BE UNDONE.',
                          style: FiloTypography.caption.copyWith(
                            color: FiloColors.destructive,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Actions: Keep Vault vs Wipe Everything
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).pop(false);
                          },
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'Keep Vault',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: FiloColors.lightTextPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.heavyImpact();
                            Navigator.of(context).pop(true);
                          },
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF4D4D), Color(0xFFFF2A6D)],
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF2A6D).withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                'Wipe Everything',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
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
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFCFFF8F5), Color(0xFCF8F4FF)],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.95), width: 1.5),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: FiloSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4.5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C243B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const Text(
                      'Auto-Lock Timeout',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.4),
                    ),
                    const SizedBox(height: FiloSpacing.sm),
                    ...options.map(
                      (mins) => ListTile(
                        title: Text(
                          mins == 0 ? 'Immediately on exit' : '$mins minutes',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        trailing: mins == currentTimeout
                            ? const Icon(Icons.check_circle_rounded, color: FiloColors.primary)
                            : null,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref.read(authNotifierProvider.notifier).setAutoLockTimeout(mins);
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF16122E) : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 14,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'settings',
          style: FiloTypography.handwriting(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : FiloColors.lightTextPrimary,
          ),
        ),
      ),
      body: FiloBackground(
        child: SafeArea(
          child: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: FiloSpacing.xl,
          vertical: FiloSpacing.sm,
        ),
        physics: const BouncingScrollPhysics(),
        children: [
          // 1. Available Storage Hero
          Text(
            'vault storage',
            style: FiloTypography.caption.copyWith(
              color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF16122E) : const Color(0xFFF5F5F7),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Text(
                  '100% SECURE',
                  style: TextStyle(
                    fontFamily: FiloTypography.fontFamily,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: FiloSpacing.md),

          // 2. Zero-Knowledge Cloud Info Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF16122E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.06),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF5F5F7),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.cloud_done_outlined,
                    color: isDark ? Colors.white : Colors.black,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Zero-Knowledge Vault',
                        style: FiloTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Files are encrypted client-side with AES-256-GCM before Telegram storage.',
                        style: FiloTypography.caption.copyWith(
                          color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: FiloSpacing.lg),

          // Security & Vault Preferences
          Text(
            'Security & Vault Preferences',
            style: FiloTypography.title3.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: FiloColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: FiloSpacing.sm),

          _buildSettingsTile(
            icon: Icons.fingerprint_rounded,
            title: 'Biometric Unlock',
            subtitle: 'Scan fingerprint or face to open vault',
            trailing: Switch(
              value: authState.isBiometricEnabled,
              activeColor: Colors.black,
              onChanged: (val) async {
                final success = await ref
                    .read(authNotifierProvider.notifier)
                    .setBiometrics(val);
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
          ),

          _buildSettingsTile(
            icon: Icons.timer_outlined,
            title: 'Auto-Lock Timeout',
            subtitle: authState.autoLockTimeoutMinutes == 0
                ? 'Immediately on exit'
                : '${authState.autoLockTimeoutMinutes} minutes',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showAutoLockPicker,
          ),

          _buildSettingsTile(
            icon: Icons.key_rounded,
            title: 'Change Master Passphrase',
            subtitle: 'Re-wrap key without re-encrypting files',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showChangePassphraseDialog,
          ),

          _buildSettingsTile(
            icon: Icons.qr_code_rounded,
            title: 'Cross-Device QR Pairing',
            subtitle: 'Show encrypted QR code to pair a new device',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showQrPairingModal,
          ),

          _buildSettingsTile(
            icon: Icons.lock_outline_rounded,
            title: 'Lock Vault Now',
            subtitle: 'Clear master keys from device memory',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              HapticFeedback.lightImpact();
              ref.read(authNotifierProvider.notifier).lockVault();
              Navigator.of(context).pop();
            },
          ),

          const SizedBox(height: FiloSpacing.md),

          // 4. Data & Storage Controls
          Text(
            'Data & Storage Controls',
            style: FiloTypography.title3.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: FiloColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: FiloSpacing.sm),

          _buildSettingsTile(
            icon: Icons.download_rounded,
            title: 'Export Everything',
            subtitle: 'Download decrypted ZIP archive of all files',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _handleExportEverything,
          ),

          _buildSettingsTile(
            icon: Icons.delete_forever_rounded,
            title: 'Delete All My Data',
            subtitle: 'Purge remote vault and wipe local database',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _handleDeleteAllData,
            isDestructive: true,
          ),

          const SizedBox(height: FiloSpacing.lg),

          // 5. Bottom Account Details Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filo Vault Account',
                      style: FiloTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: FiloColors.lightTextPrimary,
                      ),
                    ),
                    Text(
                      'Zero-Knowledge Client',
                      style: FiloTypography.caption.copyWith(
                        color: FiloColors.lightTextTertiary,
                      ),
                    ),
                  ],
                ),
                Text(
                  'v${AppConfig.appVersion}',
                  style: FiloTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: FiloSpacing.xxl),
        ],
      ),
    ),
  ),
);
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveIconColor = isDestructive
        ? FiloColors.destructive
        : (isDark ? Colors.white : Colors.black);
    final containerColor = isDestructive
        ? (isDark ? const Color(0xFF451A1A) : const Color(0xFFFEE2E2))
        : (isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFF5F5F7));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: FiloGlass(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: effectiveIconColor, size: 20),
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
