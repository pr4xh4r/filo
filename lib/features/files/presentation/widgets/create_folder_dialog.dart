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
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'Folder name',
          border: OutlineInputBorder(
            borderRadius: FiloRadius.roundedMd,
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
