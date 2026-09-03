import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../models/family_member_model.dart';
import '../../models/location_details_model.dart';
import '../../services/profile_image_service.dart';

class MemberCard extends StatefulWidget {
  final FamilyMemberModel member;
  final LocationDetailsModel? location;
  final VoidCallback onTrackOnMap;
  final VoidCallback onHistory;
  final VoidCallback? onDelete;

  const MemberCard({
    super.key,
    required this.member,
    this.location,
    required this.onTrackOnMap,
    required this.onHistory,
    this.onDelete,
  });

  @override
  State<MemberCard> createState() => _MemberCardState();
}

class _MemberCardState extends State<MemberCard> {
  File? _profileImageFile;

  @override
  void initState() {
    super.initState();
    _loadProfileImage();
  }

  @override
  void didUpdateWidget(covariant MemberCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.member.mobile != widget.member.mobile) {
      _loadProfileImage();
    }
  }

  Future<void> _loadProfileImage() async {
    if (kIsWeb) return;
    try {
      final file =
          await ProfileImageService.getProfileImageFile(widget.member.mobile);
      if (mounted) {
        setState(() {
          _profileImageFile = file;
        });
      }
    } catch (_) {}
  }

  void _showImagePickerModal() {
    if (kIsWeb) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Profile Photo for ${widget.member.name}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                title: const Text('Take Photo from Camera'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final file = await ProfileImageService.pickAndSaveProfileImage(
                    widget.member.mobile,
                    ImageSource.camera,
                  );
                  if (file != null && mounted) {
                    setState(() => _profileImageFile = file);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final file = await ProfileImageService.pickAndSaveProfileImage(
                    widget.member.mobile,
                    ImageSource.gallery,
                  );
                  if (file != null && mounted) {
                    setState(() => _profileImageFile = file);
                  }
                },
              ),
              if (_profileImageFile != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                  title: const Text('Remove Photo', style: TextStyle(color: AppColors.danger)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ProfileImageService.deleteProfileImage(widget.member.mobile);
                    if (mounted) {
                      setState(() => _profileImageFile = null);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _makeCall(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _sendSms(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('sms:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final battery = widget.location?.batteryPercentage ?? 0;
    final address = widget.location?.address ?? 'Location pending...';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Clickable Profile Image / Avatar
                GestureDetector(
                  onTap: _showImagePickerModal,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor:
                            AppColors.primaryLight.withOpacity(0.2),
                        backgroundImage: _profileImageFile != null && !kIsWeb
                            ? FileImage(_profileImageFile!)
                            : null,
                        child: _profileImageFile == null || kIsWeb
                            ? Text(
                                widget.member.name.isNotEmpty
                                    ? widget.member.name[0].toUpperCase()
                                    : 'M',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Details Area
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name & Relationship Row
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.member.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.member.relationship.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.successBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.success.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                widget.member.relationship,
                                style: const TextStyle(
                                  color: AppColors.success,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          if (widget.onDelete != null) ...[
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: widget.onDelete,
                              borderRadius: BorderRadius.circular(12),
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),

                      // Phone Number
                      Text(
                        widget.member.mobile,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Location & Battery Info
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 13,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              address,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (battery > 0) ...[
                            const SizedBox(width: 6),
                            Icon(
                              battery > 20
                                  ? Icons.battery_full_rounded
                                  : Icons.battery_alert_rounded,
                              size: 13,
                              color: battery > 20
                                  ? AppColors.success
                                  : AppColors.danger,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '$battery%',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: battery > 20
                                    ? AppColors.success
                                    : AppColors.danger,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.cardBorder),
            const SizedBox(height: 8),

            // Ultra-Mobile-Friendly 4-Button Grid / Row
            Row(
              children: [
                // 1. Call Button
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _makeCall(widget.member.mobile),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      minimumSize: const Size(0, 34),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primaryLight),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.call_rounded, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Call',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // 2. SMS Button
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _sendSms(widget.member.mobile),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      minimumSize: const Size(0, 34),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primaryLight),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.message_rounded, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'SMS',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // 3. History Button
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onHistory,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      minimumSize: const Size(0, 34),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppColors.accent,
                      side: const BorderSide(color: AppColors.accent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_rounded, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'History',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // 4. Track Button
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.onTrackOnMap,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      minimumSize: const Size(0, 34),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.navigation_rounded, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Track',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
