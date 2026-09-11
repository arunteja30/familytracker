import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import '../../constants/app_colors.dart';
import '../../models/chat_message_model.dart';
import '../../models/family_member_model.dart';
import '../../models/location_details_model.dart';
import '../../providers/family_provider.dart';
import '../../services/database_service.dart';
import '../../services/preferences_service.dart';
import '../../services/geocoding_service.dart';
import '../../utils/phone_utils.dart';
import 'member_map_screen.dart';

class FamilyChatScreen extends StatefulWidget {
  final String? familyName;
  final FamilyMemberModel? targetMember;
  final String? peerPhone;
  final String? peerName;

  const FamilyChatScreen({
    super.key,
    this.familyName,
    this.targetMember,
    this.peerPhone,
    this.peerName,
  });

  @override
  State<FamilyChatScreen> createState() => _FamilyChatScreenState();
}

class _FamilyChatScreenState extends State<FamilyChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final DatabaseService _dbService = DatabaseService();

  StreamSubscription<List<ChatMessageModel>>? _directChatSub;
  List<ChatMessageModel> _directMessages = [];
  String _userPhone = '';
  String _userName = '';
  bool _isSending = false;

  bool get isDirectChat => widget.targetMember != null || (widget.peerPhone != null && widget.peerPhone!.isNotEmpty);

  String get effectivePeerPhone =>
      widget.targetMember?.mobile ?? widget.peerPhone ?? '';

  String get effectivePeerName =>
      widget.targetMember?.name ?? widget.peerName ?? 'Family Member';

  String get directRoomId =>
      DatabaseService.getDirectChatRoomId(_userPhone, effectivePeerPhone);

  @override
  void initState() {
    super.initState();
    _userPhone = PreferencesService.getUserPhone() ?? '';
    _userName = PreferencesService.getUserName() ?? 'Family Member';

    if (isDirectChat) {
      _subscribeDirectChat();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<FamilyProvider>(context, listen: false).setChatScreenActive(true);
      _scrollToBottom();
    });
  }

  void _subscribeDirectChat() {
    _directChatSub?.cancel();
    if (directRoomId.isEmpty) return;

    _directChatSub = _dbService.streamDirectChatMessages(directRoomId).listen((msgs) {
      if (mounted) {
        setState(() {
          _directMessages = msgs;
        });
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _directChatSub?.cancel();
    Provider.of<FamilyProvider>(context, listen: false).setChatScreenActive(false);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      if (isDirectChat) {
        final message = ChatMessageModel(
          messageId: '',
          senderPhone: PhoneUtils.normalize(_userPhone),
          senderName: _userName,
          text: text,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'TEXT',
        );
        await _dbService.sendDirectChatMessage(directRoomId, message);
      } else {
        final familyProvider = Provider.of<FamilyProvider>(context, listen: false);
        await familyProvider.sendChatMessage(text);
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _shareLocation() async {
    if (_isSending) return;
    final familyProvider = Provider.of<FamilyProvider>(context, listen: false);
    setState(() => _isSending = true);

    try {
      double lat = 0.0;
      double lng = 0.0;
      String addr = '';

      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 4),
        );
        lat = pos.latitude;
        lng = pos.longitude;
        addr = await GeocodingService.getAddress(lat, lng);
      } catch (_) {}

      if (isDirectChat) {
        final message = ChatMessageModel(
          messageId: '',
          senderPhone: PhoneUtils.normalize(_userPhone),
          senderName: _userName,
          text: '📍 Shared Location',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'LOCATION',
          latitude: lat,
          longitude: lng,
          address: addr,
        );
        await _dbService.sendDirectChatMessage(directRoomId, message);
      } else {
        await familyProvider.shareCurrentLocationInChat(
          latitude: lat,
          longitude: lng,
          address: addr,
        );
      }

      _scrollToBottom();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📍 Live location shared to chat!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share location: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _openLocationOnMap(ChatMessageModel msg) {
    if (msg.latitude == null || msg.longitude == null) return;

    final dummyMember = FamilyMemberModel(
      memberId: msg.senderPhone,
      name: msg.senderName,
      mobile: msg.senderPhone,
      familyName: widget.familyName ?? '',
    );

    final locationModel = LocationDetailsModel(
      latitude: msg.latitude!,
      longitude: msg.longitude!,
      address: msg.address ?? '',
      batteryPercentage: 100,
      timeStamp: msg.timestamp,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemberMapScreen(
          member: dummyMember,
          initialLocation: locationModel,
        ),
      ),
    );
  }

  String _formatTimestamp(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isToday) {
      return DateFormat('hh:mm a').format(dt);
    }
    return DateFormat('MMM d, hh:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final familyProvider = context.watch<FamilyProvider>();
    final messages = isDirectChat ? _directMessages : familyProvider.chatMessages;
    final title = isDirectChat
        ? effectivePeerName
        : '${FamilyProvider.formatFamilyDisplayName(widget.familyName ?? familyProvider.currentFamilyName)} Chat';
    final subtitle = isDirectChat
        ? PhoneUtils.formatDisplay(effectivePeerPhone)
        : '${familyProvider.familyMembers.length} members';

    // Auto-scroll when new messages arrive
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (isDirectChat)
              Container(
                margin: const EdgeInsets.only(right: 10),
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  effectivePeerName.isNotEmpty ? effectivePeerName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            tooltip: 'Share Live Location',
            icon: const Icon(Icons.my_location_rounded),
            onPressed: _shareLocation,
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFFF4F6F9),
        child: Column(
          children: [
            // Messages List
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 64,
                            color: AppColors.textMuted.withOpacity(0.4),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isDirectChat
                                ? 'Start a conversation with $effectivePeerName!'
                                : 'Welcome to $title!',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Send a message or share location pin.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMe = PhoneUtils.isSame(msg.senderPhone, _userPhone);

                        return _buildMessageBubble(msg, isMe);
                      },
                    ),
            ),

            // Input Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    // Share Location Attachment Button
                    IconButton(
                      tooltip: 'Share Location Pin',
                      icon: const Icon(
                        Icons.add_location_alt_rounded,
                        color: AppColors.primary,
                        size: 26,
                      ),
                      onPressed: _isSending ? null : _shareLocation,
                    ),

                    // Text Field
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F2F5),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: _messageController,
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: 4,
                          minLines: 1,
                          decoration: InputDecoration(
                            hintText: isDirectChat ? 'Message $effectivePeerName...' : 'Type a family message...',
                            hintStyle: const TextStyle(fontSize: 14, color: AppColors.textMuted),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Send Button
                    Material(
                      color: AppColors.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: _isSending ? null : _sendMessage,
                        customBorder: const CircleBorder(),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          child: _isSending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessageModel msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Sender Name (if not me and group chat)
            if (!isMe && !isDirectChat)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  msg.senderName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary.withOpacity(0.9),
                  ),
                ),
              ),

            // Message Content
            if (msg.isLocation)
              _buildLocationCard(msg, isMe)
            else
              Text(
                msg.text,
                style: TextStyle(
                  fontSize: 14,
                  color: isMe ? Colors.white : AppColors.textPrimary,
                ),
              ),

            const SizedBox(height: 4),

            // Timestamp
            Text(
              _formatTimestamp(msg.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isMe
                    ? Colors.white.withOpacity(0.75)
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard(ChatMessageModel msg, bool isMe) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMe ? Colors.white.withOpacity(0.15) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe ? Colors.white.withOpacity(0.3) : const Color(0xFFBFDBFE),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.location_pin,
                color: isMe ? Colors.white : Colors.red.shade600,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                'Live Location Pin',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isMe ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (msg.address != null && msg.address!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              msg.address!,
              style: TextStyle(
                fontSize: 11,
                color: isMe ? Colors.white.withOpacity(0.9) : AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: ElevatedButton.icon(
              onPressed: () => _openLocationOnMap(msg),
              icon: const Icon(Icons.map_rounded, size: 14),
              label: const Text('View on Map', style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: isMe ? Colors.white : AppColors.primary,
                foregroundColor: isMe ? AppColors.primary : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
