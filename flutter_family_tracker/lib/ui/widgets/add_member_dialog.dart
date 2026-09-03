import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../models/family_member_model.dart';

class AddMemberDialog extends StatefulWidget {
  final String currentFamilyName;
  final Function(FamilyMemberModel member) onAdd;

  const AddMemberDialog({
    super.key,
    required this.currentFamilyName,
    required this.onAdd,
  });

  @override
  State<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<AddMemberDialog> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String _selectedRelation = 'Member';

  final List<String> _relations = [
    'Father',
    'Mother',
    'Son',
    'Daughter',
    'Spouse',
    'Brother',
    'Sister',
    'Friend',
    'Member',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    var phone = _phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    if (!phone.startsWith('+')) {
      if (phone.length == 10) {
        phone = '+91$phone';
      }
    }

    final newMember = FamilyMemberModel(
      name: name,
      mobile: phone,
      relationship: _selectedRelation,
      familyName: widget.currentFamilyName,
      memberId: DateTime.now().millisecondsSinceEpoch.toString(),
      isRegistered: false,
    );

    widget.onAdd(newMember);
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
              'Add Family Member',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter details to add to this family group.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),

            // Name
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                prefixIcon: Icon(Icons.person_rounded),
              ),
            ),
            const SizedBox(height: 14),

            // Phone
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile Number',
                hintText: 'e.g. 9876543210',
                prefixIcon: Icon(Icons.phone_rounded),
              ),
            ),
            const SizedBox(height: 14),

            // Relationship Dropdown
            DropdownButtonFormField<String>(
              value: _selectedRelation,
              decoration: const InputDecoration(
                labelText: 'Relationship',
                prefixIcon: Icon(Icons.group_rounded),
              ),
              items: _relations.map((rel) {
                return DropdownMenuItem(
                  value: rel,
                  child: Text(rel),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedRelation = val);
                }
              },
            ),
            const SizedBox(height: 24),

            // Buttons
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
                  child: const Text('Add Member'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
