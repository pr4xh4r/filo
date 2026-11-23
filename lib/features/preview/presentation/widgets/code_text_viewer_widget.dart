import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_toast.dart';

/// Interactive monospace code and text viewer with line numbers and copy action.
class CodeTextViewerWidget extends StatefulWidget {
  final String text;
  final String fileName;

  const CodeTextViewerWidget({
    super.key,
    required this.text,
    required this.fileName,
  });

  @override
  State<CodeTextViewerWidget> createState() => _CodeTextViewerWidgetState();
}

class _CodeTextViewerWidgetState extends State<CodeTextViewerWidget> {
  bool _wrapLines = false;

  String _getLanguageBadge() {
    final name = widget.fileName.toLowerCase();
    if (name.endsWith('.json')) return 'JSON';
    if (name.endsWith('.dart')) return 'DART';
    if (name.endsWith('.js') || name.endsWith('.ts')) return 'JAVASCRIPT';
    if (name.endsWith('.py')) return 'PYTHON';
    if (name.endsWith('.yaml') || name.endsWith('.yml')) return 'YAML';
    if (name.endsWith('.xml') || name.endsWith('.html')) return 'XML/HTML';
    if (name.endsWith('.css')) return 'CSS';
    if (name.endsWith('.md')) return 'MARKDOWN';
    if (name.endsWith('.sql')) return 'SQL';
    if (name.endsWith('.sh')) return 'SHELL';
    return 'TEXT';
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.text.split('\n');
    final lineCount = lines.length;

    return Column(
      children: [
        // Action Bar (Language Badge, Line Count, Wrap Toggle, Copy)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: FiloColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _getLanguageBadge(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: FiloColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$lineCount lines',
                    style: const TextStyle(fontSize: 12, color: FiloColors.lightTextTertiary),
                  ),
                ],
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _wrapLines = !_wrapLines),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _wrapLines
                            ? FiloColors.primary.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _wrapLines ? 'Wrap: On' : 'Wrap: Off',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _wrapLines ? FiloColors.primary : FiloColors.lightTextSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: 'Copy all text',
                    color: FiloColors.lightTextPrimary,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.text));
                      FiloToast.show(context, message: 'Copied to clipboard', type: FiloToastType.info);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        // Text & Line Numbers Body
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: _wrapLines ? Axis.vertical : Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Line Numbers Gutter
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(lineCount, (index) {
                      return Text(
                        '${index + 1} ',
                        style: FiloTypography.monospace.copyWith(
                          fontSize: 12,
                          color: FiloColors.lightTextTertiary.withValues(alpha: 0.45),
                          height: 1.5,
                        ),
                      );
                    }),
                  ),

                  Container(
                    width: 1,
                    height: lineCount * 18.0,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: Colors.black.withValues(alpha: 0.06),
                  ),

                  // Selectable Code Text
                  SelectableText(
                    widget.text,
                    style: FiloTypography.monospace.copyWith(
                      fontSize: 12,
                      color: FiloColors.lightTextPrimary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
