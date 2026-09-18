import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../models/family_member_model.dart';
import '../../models/location_details_model.dart';
import '../../providers/family_provider.dart';
import '../../services/profile_image_service.dart';
import '../screens/family_chat_screen.dart';
import 'buzzing_dot.dart';

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
      final file = await ProfileImageService.getProfileImageFile(widget.member.mobile);
      if (mounted) {
        setState(() => _profileImageFile = file);
      }
    } catch (_) {}
  }

  void _showImagePickerModal() {
    if (kIsWeb) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Text(
                'Profile Photo: ${widget.member.name}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary, size: 20),
                ),
                title: const Text('Take Photo from Camera', style: TextStyle(fontWeight: FontWeight.w600)),
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
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.photo_library_rounded, color: AppColors.primary, size: 20),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
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
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                    child: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                  ),
                  title: const Text('Remove Photo', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
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

  void _showMemberActionSheet(BuildContext context, bool hasUnread) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    backgroundImage: _profileImageFile != null && !kIsWeb ? FileImage(_profileImageFile!) : null,
                    child: _profileImageFile == null || kIsWeb
                        ? Text(
                            widget.member.name.isNotEmpty ? widget.member.name[0].toUpperCase() : 'M',
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.member.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        Text(
                          widget.member.mobile,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // Action 1: Call
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                  child: const Icon(Icons.phone_rounded, color: Color(0xFF16A34A), size: 20),
                ),
                title: const Text('Call Member', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(widget.member.mobile, style: const TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _makeCall(widget.member.mobile);
                },
              ),

              // Action 2: Direct Chat
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primary, size: 20),
                ),
                title: Row(
                  children: [
                    const Text('Direct Chat', style: TextStyle(fontWeight: FontWeight.w600)),
                    if (hasUnread) ...[
                      const SizedBox(width: 8),
                      const BuzzingDot(size: 7, color: Color(0xFFEF4444)),
                    ],
                  ],
                ),
                subtitle: const Text('Send direct message in circle', style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FamilyChatScreen(targetMember: widget.member),
                    ),
                  );
                },
              ),

              // Action 3: Live Track on Map
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                  child: const Icon(Icons.my_location_rounded, color: Color(0xFF2563EB), size: 20),
                ),
                title: const Text('Live Track on Map', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Focus real-time location on GPS map', style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onTrackOnMap();
                },
              ),

              // Action 4: 24h Location History
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.amber.shade50, shape: BoxShape.circle),
                  child: const Icon(Icons.history_rounded, color: Color(0xFFD97706), size: 20),
                ),
                title: const Text('Location History (24h)', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('View movements, routes & stops timeline', style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onHistory();
                },
              ),

              // Action 5: Change Profile Photo
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.purple.shade50, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF7C3AED), size: 20),
                ),
                title: const Text('Change Profile Photo', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showImagePickerModal();
                },
              ),

              // Action 6: Remove Member
              if (widget.onDelete != null)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                    child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                  ),
                  title: const Text('Remove from Family', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onDelete!();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final battery = widget.location?.batteryPercentage ?? 0;
    final address = widget.location?.address ?? 'Location syncing...';
    final familyProvider = context.watch<FamilyProvider>();
    final hasUnread = familyProvider.hasUnreadForMember(widget.member.mobile);

    Color batteryColor = AppColors.success;
    if (battery <= 20 && battery > 0) {
      batteryColor = AppColors.danger;
    } else if (battery <= 40 && battery > 0) {
      batteryColor = const Color(0xFFF59E0B);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTrackOnMap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Avatar + Name/Phone/Address + 3-Dots Menu
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Clickable Avatar with Photo Picker
                  GestureDetector(
                    onTap: _showImagePickerModal,
                    child: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 2),
                          ),
                          child: CircleAvatar(
                            radius: 24,
                            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                            backgroundImage: _profileImageFile != null && !kIsWeb ? FileImage(_profileImageFile!) : null,
                            child: _profileImageFile == null || kIsWeb
                                ? Text(
                                    widget.member.name.isNotEmpty ? widget.member.name[0].toUpperCase() : 'M',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 19,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
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
                            child: const Icon(Icons.camera_alt_rounded, size: 9, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Member Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.member.name,
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (Provider.of<FamilyProvider>(context, listen: false).isMemberAdmin(widget.member)) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.admin_panel_settings_rounded, size: 12, color: Color(0xFFB45309)),
                                    SizedBox(width: 3),
                                    Text(
                                      'Admin',
                                      style: TextStyle(
                                        color: Color(0xFFB45309),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.member.mobile,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on_rounded, size: 13, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                address,
                                style: const TextStyle(fontSize: 11.5, color: AppColors.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 3-Dots More Options Menu Button
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary, size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'More actions',
                    onPressed: () => _showMemberActionSheet(context, hasUnread),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Status & Quick Action Row
              Row(
                children: [
                  // Battery Pill
                  if (battery > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: batteryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: batteryColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            battery > 20 ? Icons.battery_std_rounded : Icons.battery_alert_rounded,
                            size: 12,
                            color: batteryColor,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$battery%',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: batteryColor),
                          ),
                        ],
                      ),
                    ),

                  const Spacer(),

                  // Quick Track Chip
                  InkWell(
                    onTap: widget.onTrackOnMap,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_rounded, size: 13, color: AppColors.primary),
                          SizedBox(width: 4),
                          Text(
                            'Track',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 6),

                  // Quick Chat Chip
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FamilyChatScreen(targetMember: widget.member),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.chat_bubble_outline_rounded, size: 13, color: AppColors.textPrimary),
                              if (hasUnread)
                                const Positioned(
                                  right: -2,
                                  top: -2,
                                  child: BuzzingDot(size: 5, color: Color(0xFFEF4444)),
                                ),
                            ],
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Chat',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
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
      ),
    );
  }
}
