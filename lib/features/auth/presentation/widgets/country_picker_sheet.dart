import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_sheet.dart';
import '../../domain/country_code.dart';

/// iOS-style searchable country code picker modal sheet.
class CountryPickerSheet extends StatefulWidget {
  final CountryCode selectedCountry;
  final ValueChanged<CountryCode> onSelect;

  const CountryPickerSheet({
    super.key,
    required this.selectedCountry,
    required this.onSelect,
  });

  static Future<CountryCode?> show(
    BuildContext context, {
    required CountryCode selectedCountry,
  }) {
    CountryCode? chosen;
    return FiloSheet.show<CountryCode>(
      context: context,
      title: 'Select Country',
      child: CountryPickerSheet(
        selectedCountry: selectedCountry,
        onSelect: (country) {
          chosen = country;
          Navigator.of(context).pop(country);
        },
      ),
    ).then((val) => val ?? chosen);
  }

  @override
  State<CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<CountryPickerSheet> {
  final _searchController = TextEditingController();
  List<CountryCode> _filtered = CountryCode.allCountries;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = CountryCode.allCountries;
      } else {
        _filtered = CountryCode.allCountries.where((c) {
          final nameMatch = c.name.toLowerCase().contains(query);
          final codeMatch = c.code.toLowerCase().contains(query);
          final dialMatch = c.dialCode.contains(query);
          return nameMatch || codeMatch || dialMatch;
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // iOS Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FiloSpacing.md,
            vertical: FiloSpacing.xs,
          ),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: isDark
                  ? FiloColors.darkSurfaceSecondary
                  : FiloColors.lightSurfaceSecondary,
              borderRadius: FiloRadius.roundedMd,
            ),
            child: TextField(
              controller: _searchController,
              style: FiloTypography.body.copyWith(
                color: isDark
                    ? FiloColors.darkTextPrimary
                    : FiloColors.lightTextPrimary,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: 'Search country or dial code...',
                hintStyle: FiloTypography.callout.copyWith(
                  color: isDark
                      ? FiloColors.darkTextTertiary
                      : FiloColors.lightTextTertiary,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: isDark
                      ? FiloColors.darkTextTertiary
                      : FiloColors.lightTextTertiary,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.cancel_rounded, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ),

        const SizedBox(height: FiloSpacing.sm),

        // Countries List with dynamic height guarding against keyboard overflow
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (MediaQuery.of(context).size.height -
                      MediaQuery.of(context).viewInsets.bottom -
                      240)
                  .clamp(140.0, MediaQuery.of(context).size.height * 0.52),
            ),
            child: _filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(FiloSpacing.xxl),
                    child: Center(
                      child: Text(
                        'No countries found',
                        style: FiloTypography.callout.copyWith(
                          color: isDark
                              ? FiloColors.darkTextTertiary
                              : FiloColors.lightTextTertiary,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _filtered.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      indent: 64,
                      color: isDark
                          ? FiloColors.darkBorder.withValues(alpha: 0.6)
                          : FiloColors.lightBorder.withValues(alpha: 0.6),
                    ),
                    itemBuilder: (context, index) {
                      final country = _filtered[index];
                      final isSelected =
                          country.code == widget.selectedCountry.code &&
                              country.dialCode == widget.selectedCountry.dialCode;

                      return InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.onSelect(country);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FiloSpacing.lg,
                            vertical: FiloSpacing.sm + 2,
                          ),
                          child: Row(
                            children: [
                              // Flag Emoji
                              Text(
                                country.flag,
                                style: const TextStyle(fontSize: 26),
                              ),
                              const SizedBox(width: FiloSpacing.md),

                              // Country Name
                              Expanded(
                                child: Text(
                                  country.name,
                                  style: FiloTypography.body.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isSelected
                                        ? FiloColors.primary
                                        : (isDark
                                            ? FiloColors.darkTextPrimary
                                            : FiloColors.lightTextPrimary),
                                  ),
                                ),
                              ),

                              // Dial Code Squircle Badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? FiloColors.primary.withValues(alpha: 0.15)
                                      : (isDark
                                          ? FiloColors.darkSurfaceSecondary
                                          : FiloColors.lightSurfaceSecondary),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(
                                  country.dialCode,
                                  style: FiloTypography.footnote.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? FiloColors.primary
                                        : (isDark
                                            ? FiloColors.darkTextSecondary
                                            : FiloColors.lightTextSecondary),
                                  ),
                                ),
                              ),

                              if (isSelected) ...[
                                const SizedBox(width: FiloSpacing.xs),
                                const Icon(
                                  Icons.check_rounded,
                                  color: FiloColors.primary,
                                  size: 18,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
