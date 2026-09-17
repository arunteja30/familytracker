import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../models/alert_item_model.dart';
import '../../services/database_service.dart';

class AlertsScreen extends StatefulWidget {
  final String familyName;
  final String userPhone;

  const AlertsScreen({
    super.key,
    required this.familyName,
    required this.userPhone,
  });

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final DatabaseService _dbService = DatabaseService();
  String _selectedFilter = 'all'; // 'all', 'sos', 'place', 'intruder', 'battery'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Alerts & Safety Feed',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              'Family: ${widget.familyName.isNotEmpty ? widget.familyName : "My Family"}',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear All Alerts',
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white),
            onPressed: () => _confirmClearAllAlerts(),
          ),
        ],
      ),
      body: StreamBuilder<List<AlertItemModel>>(
        stream: _dbService.streamFamilyAlerts(widget.familyName),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allAlerts = snapshot.data ?? [];
          final filteredAlerts = _filterAlerts(allAlerts);

          final sosCount = allAlerts.where((a) => a.type == AlertType.sos).length;
          final placesCount = allAlerts.where((a) => a.type == AlertType.placeArrival || a.type == AlertType.placeDeparture).length;
          final intruderCount = allAlerts.where((a) => a.type == AlertType.intruder).length;
          final batteryCount = allAlerts.where((a) => a.type == AlertType.batteryLow).length;

          return Column(
            children: [
              // 1. 24-Hour Self-Delete Notice Banner
              _buildTtlBanner(),

              // 2. Filter Category Chips
              _buildFilterChips(
                totalCount: allAlerts.length,
                sosCount: sosCount,
                placesCount: placesCount,
                intruderCount: intruderCount,
                batteryCount: batteryCount,
              ),

              // 3. Alerts Feed List or Empty State
              Expanded(
                child: filteredAlerts.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: filteredAlerts.length,
                        itemBuilder: (context, index) {
                          final alert = filteredAlerts[index];
                          return _buildAlertCard(alert);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<AlertItemModel> _filterAlerts(List<AlertItemModel> alerts) {
    switch (_selectedFilter) {
      case 'sos':
        return alerts.where((a) => a.type == AlertType.sos).toList();
      case 'places':
        return alerts.where((a) => a.type == AlertType.placeArrival || a.type == AlertType.placeDeparture).toList();
      case 'intruder':
        return alerts.where((a) => a.type == AlertType.intruder).toList();
      case 'battery':
        return alerts.where((a) => a.type == AlertType.batteryLow).toList();
      default:
        return alerts;
    }
  }

  Widget _buildTtlBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7), // Warm Amber
        border: Border(bottom: BorderSide(color: Colors.amber.shade200)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_delete_rounded, size: 16, color: Colors.amber.shade900),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '24-Hour Auto-Delete Active: Alerts automatically disappear 24 hours after occurrence.',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips({
    required int totalCount,
    required int sosCount,
    required int placesCount,
    required int intruderCount,
    required int batteryCount,
  }) {
    final chips = [
      {'key': 'all', 'label': 'All ($totalCount)', 'icon': Icons.all_inbox_rounded},
      {'key': 'sos', 'label': '🚨 SOS ($sosCount)', 'icon': Icons.emergency_rounded},
      {'key': 'places', 'label': '🏠 Places ($placesCount)', 'icon': Icons.place_rounded},
      {'key': 'intruder', 'label': '📸 Intruder ($intruderCount)', 'icon': Icons.security_rounded},
      {'key': 'battery', 'label': '🔋 Battery ($batteryCount)', 'icon': Icons.battery_alert_rounded},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: chips.map((c) {
          final isSelected = _selectedFilter == c['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(c['label'] as String),
              selected: isSelected,
              selectedColor: AppColors.primary,
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? AppColors.primary : Colors.grey.shade300,
                ),
              ),
              onSelected: (_) {
                setState(() => _selectedFilter = c['key'] as String);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAlertCard(AlertItemModel alert) {
    final timeStr = DateFormat('hh:mm a • dd MMM').format(
      DateTime.fromMillisecondsSinceEpoch(alert.timestamp),
    );
    final color = alert.type.color;
    final isSos = alert.type == AlertType.sos;

    return Dismissible(
      key: Key(alert.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
      ),
      onDismissed: (_) {
        _dbService.deleteAlert(widget.familyName, alert.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alert dismissed.')),
        );
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSos ? Colors.red.shade300 : AppColors.cardBorder,
            width: isSos ? 1.5 : 1.0,
          ),
        ),
        elevation: isSos ? 3 : 1,
        color: isSos ? const Color(0xFFFEF2F2) : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Type Badge + 24h Expiry Pill + More Action
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(alert.type.icon, size: 14, color: color),
                        const SizedBox(width: 4),
                        Text(
                          alert.type.displayName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // TTL Countdown Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_outlined, size: 11, color: Colors.grey.shade600),
                        const SizedBox(width: 3),
                        Text(
                          alert.remainingTimeText,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textSecondary),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    onPressed: () => _dbService.deleteAlert(widget.familyName, alert.id),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                alert.title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),

              // Body
              Text(
                alert.body,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.3),
              ),
              const SizedBox(height: 10),

              // Footer: Timestamp + Quick Action Buttons
              Row(
                children: [
                  Icon(Icons.access_time_rounded, size: 12, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    timeStr,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const Spacer(),
                  // Phone Call Action if Mobile available
                  if (alert.memberMobile.isNotEmpty)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _callPhone(alert.memberMobile),
                      icon: const Icon(Icons.phone_rounded, size: 13, color: AppColors.primary),
                      label: const Text('Call', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_off_outlined, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            const Text(
              'All Clear • No Active Alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Safety alerts, place arrivals/departures, SOS distress triggers, and battery notifications from the past 24 hours will appear here.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _confirmClearAllAlerts() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Alerts?'),
        content: const Text('Are you sure you want to clear all active alerts from the safety feed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await _dbService.clearAllAlerts(widget.familyName);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: success ? AppColors.success : Colors.red,
                    content: Text(success ? 'All alerts cleared.' : 'Failed to clear alerts.'),
                  ),
                );
              }
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
