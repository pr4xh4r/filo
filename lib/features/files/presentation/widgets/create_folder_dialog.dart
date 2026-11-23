import 'package:flutter/material.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../shared/components/filo_button.dart';

/// Modal dialog for creating a virtual folder.
class CreateFolderDialog extends StatefulWidget {
  final void Function(String name) onCreate;

  const CreateFolderDialog({super.key, required this.onCreate});

  static Future<void> show(
    BuildContext context, {
    required void Function(String name) onCreate,
  }) {
    return showDialog(
      context: context,
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
    return AlertDialog(
      title: const Text('New Folder'),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F7),
          borderRadius: FiloRadius.roundedMd,
          border: Border.all(color: const Color(0xFFE5E5EA)),
        ),
        child: TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            filled: false,
            fillColor: Colors.transparent,
            hintText: 'Folder name',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FiloButton(
          label: 'Create',
          size: FiloButtonSize.small,
          onPressed: _submit,
        ),
      ],
    );
  }
}
