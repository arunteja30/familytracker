import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';

class GroupSwitcherDialog extends StatefulWidget {
  final String currentGroup;
  final Function(String newGroup) onSwitch;

  const GroupSwitcherDialog({
    super.key,
    required this.currentGroup,
    required this.onSwitch,
  });

  @override
  State<GroupSwitcherDialog> createState() => _GroupSwitcherDialogState();
}

class _GroupSwitcherDialogState extends State<GroupSwitcherDialog> {
  final _groupNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _groupNameController.text = widget.currentGroup;
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  void _submit() {
    final group = _groupNameController.text.trim();
    if (group.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }
    widget.onSwitch(group);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Switch Family Group',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter a family group name to view or create.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _groupNameController,
              decoration: const InputDecoration(
                labelText: 'Group Name',
                hintText: 'e.g. MyFamily, SharmaFamily',
                prefixIcon: Icon(Icons.family_restroom_rounded),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _submit,
                  child: const Text('Switch Group'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
