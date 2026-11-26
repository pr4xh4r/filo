import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_button.dart';

/// Modal dialog for creating a virtual folder with Ethereal Dawn frosted glass design.
class CreateFolderDialog extends StatefulWidget {
  final void Function(String name) onCreate;

  const CreateFolderDialog({super.key, required this.onCreate});

  static Future<void> show(
    BuildContext context, {
    required void Function(String name) onCreate,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) => CreateFolderDialog(onCreate: onCreate),
    );
  }

  @override
  State<CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<CreateFolderDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) {
      widget.onCreate(name);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF9F7), Color(0xFFFBF4FF)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.85),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.9,
                maxWidth: 480,
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: FiloColors.primary.withValues(alpha: 0.1),
                        borderRadius: FiloRadius.roundedMd,
                      ),
                      child: const Icon(
                        Icons.create_new_folder_outlined,
                        color: FiloColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'New Folder',
                      style: FiloTypography.title3.copyWith(
                        fontWeight: FontWeight.w700,
                        color: FiloColors.lightTextPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                  ),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                      fontFamily: FiloTypography.fontFamily,
                      fontSize: 15,
                      color: FiloColors.lightTextPrimary,
                    ),
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      filled: false,
                      hintText: 'Folder name',
                      hintStyle: TextStyle(
                        fontFamily: FiloTypography.fontFamily,
                        color: FiloColors.lightTextTertiary,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontFamily: FiloTypography.fontFamily,
                          color: FiloColors.lightTextSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FiloButton(
                      label: 'Create',
                      size: FiloButtonSize.small,
                      onPressed: _submit,
                    ),
                  ],
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
}
