import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/filo_colors.dart';
import '../../core/theme/filo_typography.dart';
import '../../shared/components/filo_sheet.dart';

enum CloudProviderType {
  telegram,
}

enum PrivacyModeType {
  encrypted,
  viewable,
}

/// Interactive Apple-grade conversational cloud & privacy mode selector.
///
/// Features:
/// - Handwritten Ethereal Dawn header ("Choose your cloud & privacy")
/// - Dedicated Telegram Cloud storage backend (Unlimited)
/// - Interactive mode selection: Private & Encrypted (Unlimited, no limits) vs Viewable (TG 2GB / 4GB limit)
/// - Fluid animated selection feedback with haptics
class CloudStorageSelectorSheet extends StatefulWidget {
  final CloudProviderType initialProvider;
  final PrivacyModeType initialMode;
  final Function(CloudProviderType provider, PrivacyModeType mode) onSelected;

  const CloudStorageSelectorSheet({
    super.key,
    this.initialProvider = CloudProviderType.telegram,
    this.initialMode = PrivacyModeType.encrypted,
    required this.onSelected,
  });

  static Future<void> show(
    BuildContext context, {
    CloudProviderType initialProvider = CloudProviderType.telegram,
    PrivacyModeType initialMode = PrivacyModeType.encrypted,
    required Function(CloudProviderType provider, PrivacyModeType mode) onSelected,
  }) {
    return FiloSheet.show(
      context: context,
      child: CloudStorageSelectorSheet(
        initialProvider: initialProvider,
        initialMode: initialMode,
        onSelected: onSelected,
      ),
    );
  }

  @override
  State<CloudStorageSelectorSheet> createState() => _CloudStorageSelectorSheetState();
}

class _CloudStorageSelectorSheetState extends State<CloudStorageSelectorSheet> {
  late CloudProviderType _selectedProvider;
  late PrivacyModeType _selectedMode;

  @override
  void initState() {
    super.initState();
    _selectedProvider = widget.initialProvider;
    _selectedMode = widget.initialMode;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handwritten Ethereal Headline
          Center(
            child: Text(
              'Storage & privacy mode',
              textAlign: TextAlign.center,
              style: FiloTypography.handwriting(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : FiloColors.lightTextPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Select how your files should be stored and encrypted in Telegram.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
            ),
          ),
          const SizedBox(height: 20),

          // Section 1: Cloud Provider
          Text(
            '1. CLOUD STORAGE PLATFORM',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              // Telegram Provider Card
              Expanded(
                child: _buildProviderCard(
                  context: context,
                  provider: CloudProviderType.telegram,
                  title: 'Telegram Cloud',
                  badge: 'Unlimited Free',
                  icon: Icons.send_rounded,
                  isDark: isDark,
                  isSelected: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Section 2: Privacy Mode
          Text(
            '2. HOW WOULD YOU LIKE TO STORE YOUR FILES?',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
            ),
          ),
          const SizedBox(height: 8),

          // Mode A: Encrypted
          _buildModeOption(
            context: context,
            mode: PrivacyModeType.encrypted,
            title: 'Private & Encrypted',
            badge: 'Unlimited • No Limits',
            description:
                'Zero-knowledge secrecy. Neither Telegram nor anyone else can see what is inside. Unlimited storage with no file size limits.',
            icon: Icons.visibility_off_rounded,
            isDark: isDark,
            isSelected: _selectedMode == PrivacyModeType.encrypted,
          ),
          const SizedBox(height: 10),

          // Mode B: Viewable
          _buildModeOption(
            context: context,
            mode: PrivacyModeType.viewable,
            title: 'Viewable Anywhere',
            badge: '2 GB / 4 GB Premium limit',
            description:
                'Direct access. Files are stored standard in Telegram (2 GB standard, 4 GB Telegram Premium limit per file). You can open them from any Telegram app.',
            icon: Icons.visibility_rounded,
            isDark: isDark,
            isSelected: _selectedMode == PrivacyModeType.viewable,
          ),
          const SizedBox(height: 24),

          // Confirm Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: FiloColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 4,
            ),
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.of(context).pop();
              widget.onSelected(_selectedProvider, _selectedMode);
            },
            child: const Text(
              'Save Storage Preference',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCard({
    required BuildContext context,
    required CloudProviderType provider,
    required String title,
    required String badge,
    required IconData icon,
    required bool isDark,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedProvider = provider);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white.withValues(alpha: 0.16) : Colors.black)
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? (isDark ? Colors.white : Colors.black)
                : (isDark ? Colors.white12 : Colors.black12),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark ? Colors.white24 : Colors.white12)
                        : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
                const Spacer(),
                if (isSelected)
                  const Icon(Icons.check_circle_rounded, size: 18, color: Colors.white),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontFamily: FiloTypography.fontFamily,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white : FiloColors.lightTextPrimary),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              badge,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Colors.white70
                    : (isDark ? Colors.white60 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeOption({
    required BuildContext context,
    required PrivacyModeType mode,
    required String title,
    required String badge,
    required String description,
    required IconData icon,
    required bool isDark,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedMode = mode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white.withValues(alpha: 0.16) : Colors.black)
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? (isDark ? Colors.white : Colors.black)
                : (isDark ? Colors.white12 : Colors.black12),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark ? Colors.white24 : Colors.white12)
                    : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 17,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: FiloTypography.fontFamily,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white : FiloColors.lightTextPrimary),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '• $badge',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white70
                                : (isDark ? Colors.white60 : Colors.black54),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: isSelected
                          ? Colors.white70
                          : (isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(left: 6, top: 4),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white30 : Colors.black26),
                  width: 2,
                ),
                color: isSelected ? Colors.white : Colors.transparent,
              ),
              child: isSelected
                  ? Center(
                      child: Icon(
                        Icons.check_rounded,
                        size: 12,
                        color: isDark ? const Color(0xFF1E1E2C) : Colors.black,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
