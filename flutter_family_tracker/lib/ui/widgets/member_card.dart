import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../models/family_member_model.dart';
import '../../models/location_details_model.dart';
import '../../providers/family_provider.dart';
import '../../services/profile_image_service.dart';
import '../../services/preferences_service.dart';
import '../../services/database_service.dart';
import '../../utils/proximity_utils.dart';
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

  String _formatRelativeTime(int ts, String dateStr) {
    int ms = ts;
    if (ms > 0 && ms < 10000000000) ms *= 1000;
    if (ms <= 0 && dateStr.isNotEmpty) {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) ms = parsed.millisecondsSinceEpoch;
    }
    if (ms <= 0) return '';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.isNegative || diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  Color _getPresenceColor(int ts, String dateStr) {
    int ms = ts;
    if (ms > 0 && ms < 10000000000) ms *= 1000;
    if (ms <= 0 && dateStr.isNotEmpty) {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) ms = parsed.millisecondsSinceEpoch;
    }
    if (ms <= 0) return const Color(0xFF94A3B8);
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes <= 15) return const Color(0xFF10B981);
    if (diff.inMinutes <= 60) return const Color(0xFFF59E0B);
    return const Color(0xFF94A3B8);
  }

  bool _isRecentlyActive(int ts, String dateStr) {
    int ms = ts;
    if (ms > 0 && ms < 10000000000) ms *= 1000;
    if (ms <= 0 && dateStr.isNotEmpty) {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) ms = parsed.millisecondsSinceEpoch;
    }
    if (ms <= 0) return false;
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    return diff.inMinutes <= 15;
  }

  Widget _buildBadgePill({
    required IconData icon,
    required String text,
    required Color color,
    required Color bgColor,
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: borderColor ?? color.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11.5, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color fgColor,
    required VoidCallback onTap,
    bool hasBadge = false,
    bool isPrimary = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: isPrimary ? null : bgColor,
            gradient: isPrimary ? AppColors.buttonGradient : null,
            borderRadius: BorderRadius.circular(10),
            border: isPrimary
                ? null
                : Border.all(color: fgColor.withValues(alpha: 0.2), width: 1),
            boxShadow: isPrimary
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: 8.5, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 14, color: fgColor),
                  if (hasBadge)
                    const Positioned(
                      right: -3,
                      top: -3,
                      child: BuzzingDot(size: 6, color: Color(0xFFEF4444)),
                    ),
                ],
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: fgColor,
                    letterSpacing: -0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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

    final userPhone = PreferencesService.getUserPhone() ?? '';
    final isSelf = DatabaseService.matchPhones(widget.member.mobile, userPhone);
    final isMemberAdmin =
        familyProvider.isMemberAdmin(widget.member) || widget.member.isAdmin;

    LocationDetailsModel? currentUserLoc;
    if (!isSelf && userPhone.isNotEmpty) {
      for (final entry in familyProvider.memberLocations.entries) {
        if (DatabaseService.matchPhones(entry.key, userPhone)) {
          currentUserLoc = entry.value;
          break;
        }
      }
    }
    final relativeDistance = (!isSelf && currentUserLoc != null && widget.location != null)
        ? ProximityUtils.getRelativeDistance(
            userLat: currentUserLoc.latitude,
            userLng: currentUserLoc.longitude,
            targetLat: widget.location!.latitude,
            targetLng: widget.location!.longitude,
          )
        : '';

    final relativeTime = _formatRelativeTime(
      widget.location?.timeStamp ?? 0,
      widget.location?.date ?? '',
    );
    final presenceColor = _getPresenceColor(
      widget.location?.timeStamp ?? 0,
      widget.location?.date ?? '',
    );
    final isRecentlyActive = _isRecentlyActive(
      widget.location?.timeStamp ?? 0,
      widget.location?.date ?? '',
    );
    final relationshipLabel = widget.member.relationship.trim();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.cardBorder.withValues(alpha: 0.8),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        onTap: widget.onTrackOnMap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Avatar with Status Ring + Name & Badges + 3-Dots Menu
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Clickable Avatar with Dynamic Status Ring
                  GestureDetector(
                    onTap: _showImagePickerModal,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: isRecentlyActive
                                  ? [const Color(0xFF10B981), const Color(0xFF06B6D4)]
                                  : [AppColors.primaryLight, AppColors.primary],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(1.5),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: CircleAvatar(
                              radius: 23,
                              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
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
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        // Presence status dot indicator
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 12.5,
                            height: 12.5,
                            decoration: BoxDecoration(
                              color: presenceColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: presenceColor.withValues(alpha: 0.4),
                                  blurRadius: 3,
                                  spreadRadius: 0.5,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Member Name, Role, Relation & Phone
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.member.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isMemberAdmin) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.shield_rounded,
                                      size: 10,
                                      color: Color(0xFFB45309),
                                    ),
                                    SizedBox(width: 2.5),
                                    Text(
                                      'Admin',
                                      style: TextStyle(
                                        color: Color(0xFFB45309),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (isSelf) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: const Text(
                                  'You',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                            if (relationshipLabel.isNotEmpty &&
                                !isMemberAdmin &&
                                relationshipLabel.toLowerCase() != 'self') ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Text(
                                  relationshipLabel,
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(
                              Icons.phone_iphone_rounded,
                              size: 12.5,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              widget.member.mobile,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 3-Dots More Options Menu Button
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary, size: 21),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'More actions',
                    onPressed: () => _showMemberActionSheet(context, hasUnread),
                  ),
                ],
              ),

              const SizedBox(height: 11),

              // Middle: Status & Context Strip
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.bgSurfaceElevated,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.7)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Address Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3.5),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            size: 12.5,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            address,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    // Badges row: Proximity, Battery, Time, Movement
                    if (battery > 0 ||
                        relativeDistance.isNotEmpty ||
                        relativeTime.isNotEmpty ||
                        (widget.location?.isMoving ?? false)) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        children: [
                          // Proximity Pill
                          if (relativeDistance.isNotEmpty)
                            _buildBadgePill(
                              icon: Icons.near_me_rounded,
                              text: relativeDistance,
                              color: const Color(0xFF0284C7),
                              bgColor: const Color(0xFFE0F2FE),
                            ),

                          // Battery Pill
                          if (battery > 0)
                            _buildBadgePill(
                              icon: battery > 20
                                  ? Icons.battery_std_rounded
                                  : Icons.battery_alert_rounded,
                              text: '$battery%',
                              color: batteryColor,
                              bgColor: batteryColor.withValues(alpha: 0.12),
                            ),

                          // Relative Time Pill
                          if (relativeTime.isNotEmpty)
                            _buildBadgePill(
                              icon: Icons.access_time_rounded,
                              text: relativeTime,
                              color: AppColors.textSecondary,
                              bgColor: Colors.white,
                              borderColor: AppColors.cardBorder,
                            ),

                          // Moving Status Pill
                          if (widget.location?.isMoving == true)
                            _buildBadgePill(
                              icon: Icons.directions_car_rounded,
                              text: 'Moving • ${widget.location!.formattedSpeed}',
                              color: const Color(0xFF16A34A),
                              bgColor: const Color(0xFFDCFCE7),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 11),

              // Bottom: Direct 1-Tap Action Bar
              Row(
                children: [
                  // 1-Tap Call
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.phone_rounded,
                      label: 'Call',
                      bgColor: const Color(0xFFDCFCE7),
                      fgColor: const Color(0xFF16A34A),
                      onTap: () => _makeCall(widget.member.mobile),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // 1-Tap Chat
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'Chat',
                      bgColor: const Color(0xFFEEF2FF),
                      fgColor: AppColors.primary,
                      hasBadge: hasUnread,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FamilyChatScreen(targetMember: widget.member),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 6),

                  // 1-Tap History
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.history_rounded,
                      label: 'History',
                      bgColor: const Color(0xFFFEF3C7),
                      fgColor: const Color(0xFFD97706),
                      onTap: widget.onHistory,
                    ),
                  ),
                  const SizedBox(width: 6),

                  // 1-Tap Track (Primary CTA)
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.navigation_rounded,
                      label: 'Track',
                      bgColor: AppColors.primary,
                      fgColor: Colors.white,
                      isPrimary: true,
                      onTap: widget.onTrackOnMap,
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
