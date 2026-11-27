import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/database/filo_database.dart' show StorageUsageStats;
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_background.dart';
import '../../../../shared/components/filo_glass.dart';
import '../../../../shared/components/filo_progress_ring.dart';
import '../../../../shared/components/filo_qr_card.dart';
import '../../../../shared/components/filo_qr_scanner_screen.dart';
import '../../../../shared/components/filo_sheet.dart';
import '../../../../shared/components/filo_toast.dart';
import '../../../../shared/components/handwriting_text.dart';
import '../../../auth/domain/auth_state.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../files/presentation/providers/file_browser_provider.dart';
import '../../../broadcast/domain/broadcast_service.dart';
import '../../../sync/domain/index_sync_service.dart';
import '../../../transfer/domain/vault_export_service.dart';
import '../../../transfer/presentation/providers/export_provider.dart';
import '../widgets/export_everything_sheet.dart';

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
    bool obscureOld = true;
    bool obscureNew = true;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.85,
                      maxWidth: 480,
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                        'Change Passphrase',
                        style: FiloTypography.title3.copyWith(
                          color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Your encryption key will be safely updated without re-uploading files.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Current Passphrase Input (Circular stadium pill)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        child: TextField(
                          controller: oldController,
                          obscureText: obscureOld,
                          textAlignVertical: TextAlignVertical.center,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            hintText: 'Current Passphrase',
                            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureOld ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 20,
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setDialogState(() => obscureOld = !obscureOld);
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // New Passphrase Input (Circular stadium pill)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        child: TextField(
                          controller: newController,
                          obscureText: obscureNew,
                          textAlignVertical: TextAlignVertical.center,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            hintText: 'New Passphrase (min 8 chars)',
                            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 20,
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setDialogState(() => obscureNew = !obscureNew);
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text(
                              'Cancel',
                              style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: FiloColors.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                            ),
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
                                final masterKey = ref.read(authNotifierProvider).masterKey;
                                if (masterKey != null) {
                                  ref.read(indexSyncServiceProvider).triggerAutoSync(
                                        masterKey: masterKey,
                                        delay: const Duration(milliseconds: 200),
                                      );
                                }
                                if (ctx.mounted) {
                                  Navigator.of(ctx).pop();
                                  FiloToast.show(
                                    context,
                                    message: 'Passphrase successfully updated',
                                    type: FiloToastType.success,
                                  );
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  FiloToast.show(
                                    context,
                                    message: 'Failed to verify current passphrase',
                                    type: FiloToastType.error,
                                  );
                                }
                              }
                            },
                            child: const Text('Update', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
      },
    );
  },
);
  }

  void _showScanOrPasteTokenDialog() {
    final tokenController = TextEditingController();

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.85,
                  maxWidth: 480,
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    'Pair New Device',
                    style: FiloTypography.title3.copyWith(
                      color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Paste your vault pairing token below to sync files across devices.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: TextField(
                      controller: tokenController,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'filo://vault?bundle=... or JSON',
                        hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: FiloColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                        ),
                        onPressed: () async {
                          final token = tokenController.text.trim();
                          if (token.isEmpty) return;

                          try {
                            String rawJson = token;
                            if (token.startsWith('filo://vault?bundle=')) {
                              final b64 = token.substring('filo://vault?bundle='.length);
                              rawJson = utf8.decode(base64Url.decode(b64));
                            }
                            final data = json.decode(rawJson) as Map<String, dynamic>;
                            final repo = ref.read(authRepositoryProvider);
                            await repo.importVaultKeyBundle(data);
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                              ref.read(authNotifierProvider.notifier).initialize();
                              FiloToast.show(context, message: 'Vault paired successfully!', type: FiloToastType.success);
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              FiloToast.show(context, message: 'Invalid pairing token', type: FiloToastType.error);
                            }
                          }
                        },
                        child: const Text('Sync Vault', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
  },
);
  }

  Future<void> _handleLiveQrScan() async {
    final scannedData = await FiloQrScannerScreen.open(
      context,
      title: 'Scan QR Code',
      hint: 'Align the QR code within the frame to pair',
    );
    if (!mounted || scannedData == null) return;

    if (scannedData == 'MANUAL_ENTRY') {
      _showScanOrPasteTokenDialog();
      return;
    }

    await _pairWithTokenString(scannedData);
  }

  Future<void> _pairWithTokenString(String token) async {
    try {
      String rawJson = token.trim();
      if (rawJson.startsWith('filo://vault?bundle=')) {
        final b64 = rawJson.substring('filo://vault?bundle='.length);
        rawJson = utf8.decode(base64Url.decode(b64));
      }
      final data = json.decode(rawJson) as Map<String, dynamic>;
      final repo = ref.read(authRepositoryProvider);
      await repo.importVaultKeyBundle(data);
      if (mounted) {
        ref.read(authNotifierProvider.notifier).initialize();
        FiloToast.show(context, message: 'Vault paired successfully!', type: FiloToastType.success);
      }
    } catch (e) {
      if (mounted) {
        FiloToast.show(context, message: 'Invalid pairing token', type: FiloToastType.error);
      }
    }
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
      builder: (context) => FiloQrCard(
        title: 'Cross-Device Pairing',
        subtitle: 'Scan this QR code from another device running Filo, or use the actions below.',
        data: pairingPayload,
        onScanPressed: () {
          Navigator.of(context).pop();
          _handleLiveQrScan();
        },
        onPairPressed: () {
          Navigator.of(context).pop();
          _showScanOrPasteTokenDialog();
        },
      ),
    );
  }

  Future<void> _handleExportEverything() async {
    final authState = ref.read(authNotifierProvider);
    if (authState.masterKey == null) {
      FiloToast.show(
        context,
        message: 'Vault is locked. Unlock before exporting.',
        type: FiloToastType.error,
      );
      return;
    }

    await ExportEverythingSheet.show(context);
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
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
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
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
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
      ),
    );
  }

  void _showTelegramStorageGuide() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    FiloSheet.show(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF2AABEE).withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_outlined,
                color: Color(0xFF2AABEE),
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: HandwritingText(
              text: 'Telegram Storage Guide',
              style: FiloTypography.handwriting(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : FiloColors.lightTextPrimary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Filo turns Telegram into your private, unlimited cloud drive with two distinct storage modes.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: FiloTypography.fontFamily,
              fontSize: 13,
              color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 20),

          // Block 1: Encrypted (Unlimited)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: FiloColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.lock_rounded, size: 18, color: FiloColors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Encrypted',
                        style: TextStyle(
                          fontFamily: FiloTypography.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: FiloColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: const Text(
                        'Unlimited',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: FiloColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'This data is encrypted and will only be decrypted by Filo. Even Telegram cannot see your files.',
                  style: TextStyle(
                    fontFamily: FiloTypography.fontFamily,
                    fontSize: 13,
                    color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Block 2: Viewable
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2AABEE).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.remove_red_eye_rounded, size: 18, color: Color(0xFF2AABEE)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Viewable',
                        style: TextStyle(
                          fontFamily: FiloTypography.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2AABEE).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: const Text(
                        '2 GB / 4 GB',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2AABEE),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'This data will be viewable anywhere in Telegram. Standard limit is 2 GB per file; Telegram Premium unlocks 4 GB per file.',
                  style: TextStyle(
                    fontFamily: FiloTypography.fontFamily,
                    fontSize: 13,
                    color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final exportState = ref.watch(vaultExportProvider);
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
          'Settings',
          style: FiloTypography.title2.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 22,
            letterSpacing: -0.5,
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
          // 1. Used Storage
          Text(
            'Used Space',
            style: FiloTypography.caption.copyWith(
              color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: FiloTypography.fontFamily,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isLoading
                ? 'Loading...'
                : (_storageStats != null && _storageStats!.totalBytes > 0
                    ? HashUtils.formatBytes(_storageStats!.totalBytes)
                    : '0 KB used'),
            style: FiloTypography.title1.copyWith(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.0,
              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
            ),
          ),

          const SizedBox(height: FiloSpacing.md),

          // 2. Telegram Connected Profile Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF16122E) : Colors.white,
              borderRadius: BorderRadius.circular(22),
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
                _buildTelegramAvatar(authState, isDark),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _getTelegramPrimaryName(authState),
                              style: FiloTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF34C759).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF34C759),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'Connected',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF248A3D),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (authState.telegramDisplayName != null &&
                          authState.telegramDisplayName!.isNotEmpty &&
                          authState.telegramUserName != null &&
                          authState.telegramUserName!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '@${authState.telegramUserName!}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2AABEE),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 3),
                      Text(
                        authState.telegramUserId != null
                            ? 'Telegram ID: ${authState.telegramUserId}'
                            : 'Encrypted storage session active',
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

          const SizedBox(height: FiloSpacing.md),

          // Telegram Storage Architecture Guide Tile
          _buildSettingsTile(
            icon: Icons.menu_book_rounded,
            title: 'Telegram Cloud Guide',
            subtitle: 'Read about Encrypted (unlimited) & Viewable (2GB/4GB)',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showTelegramStorageGuide,
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
            icon: Icons.system_update_rounded,
            title: 'Check for Updates',
            subtitle: 'Filo v${AppConfig.appVersion} • Tap to check',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              HapticFeedback.lightImpact();
              FiloToast.show(context, message: 'Checking for updates...', type: FiloToastType.info);
              await ref.read(broadcastNotifierProvider.notifier).refresh();
              final update = ref.read(broadcastNotifierProvider).update;
              if (mounted) {
                if (update != null) {
                  FiloToast.show(context, message: 'Update available: v${update.latestVersion}', type: FiloToastType.success);
                } else {
                  FiloToast.show(context, message: 'Filo is up to date (v${AppConfig.appVersion})', type: FiloToastType.success);
                }
              }
            },
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
            subtitle: _exportTileSubtitle(exportState),
            trailing: exportState.isActive
                ? FiloProgressRing(
                    value: exportState.progress > 0 ? exportState.progress : null,
                    size: 20,
                    strokeWidth: 2.2,
                  )
                : const Icon(Icons.chevron_right_rounded),
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
                      'Secure Storage Client',
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

  String _exportTileSubtitle(VaultExportState exportState) {
    if (exportState.isActive) {
      final pct = (exportState.progress * 100).clamp(0, 100).toInt();
      return 'Exporting ${exportState.completedFiles}/${exportState.totalFiles} files • $pct%';
    }
    if (exportState.status == VaultExportStatus.paused ||
        exportState.status == VaultExportStatus.partialNeedsAction) {
      return 'Resumable export: ${exportState.completedFiles}/${exportState.totalFiles} files ready';
    }
    return 'Stream decrypted Zip64 archive of all files';
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

  String _getTelegramPrimaryName(FiloAuthState authState) {
    if (authState.telegramDisplayName != null && authState.telegramDisplayName!.isNotEmpty) {
      return authState.telegramDisplayName!;
    }
    if (authState.telegramUserName != null && authState.telegramUserName!.isNotEmpty) {
      return authState.telegramUserName!.startsWith('@')
          ? authState.telegramUserName!
          : '@${authState.telegramUserName!}';
    }
    return 'Telegram Account';
  }

  Widget _buildTelegramAvatar(FiloAuthState authState, bool isDark) {
    final photoPath = authState.telegramProfilePhotoPath;
    final hasValidFile = photoPath != null && photoPath.isNotEmpty && File(photoPath).existsSync();

    if (hasValidFile) {
      final isFlutterTest = const bool.fromEnvironment('FLUTTER_TEST') ||
          (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST'));

      return Container(
        key: const ValueKey('telegram_avatar_image'),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipOval(
          child: isFlutterTest
              ? Container(
                  color: const Color(0xFF2AABEE),
                  child: const Center(
                    child: Icon(Icons.person, color: Colors.white, size: 24),
                  ),
                )
              : Image.file(
                  File(photoPath),
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildFallbackAvatar(authState, isDark),
                ),
        ),
      );
    }

    return _buildFallbackAvatar(authState, isDark);
  }

  Widget _buildFallbackAvatar(FiloAuthState authState, bool isDark) {
    String initial = 'T';
    if (authState.telegramDisplayName != null && authState.telegramDisplayName!.isNotEmpty) {
      initial = authState.telegramDisplayName![0].toUpperCase();
    } else if (authState.telegramUserName != null && authState.telegramUserName!.isNotEmpty) {
      initial = authState.telegramUserName!.replaceFirst('@', '')[0].toUpperCase();
    }

    return Container(
      key: const ValueKey('telegram_avatar_fallback'),
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: FiloColors.primary,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
