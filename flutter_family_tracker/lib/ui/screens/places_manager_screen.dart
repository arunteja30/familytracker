import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../../constants/app_colors.dart';
import '../../models/family_member_model.dart';
import '../../models/geofence_place_model.dart';
import '../../models/place_event_model.dart';
import '../../services/database_service.dart';
import 'place_picker_screen.dart';

class PlacesManagerScreen extends StatefulWidget {
  final String familyName;
  final String userPhone;
  final double? initialLat;
  final double? initialLng;

  const PlacesManagerScreen({
    super.key,
    required this.familyName,
    required this.userPhone,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<PlacesManagerScreen> createState() => _PlacesManagerScreenState();
}

class _PlacesManagerScreenState extends State<PlacesManagerScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseService _dbService = DatabaseService();
  late TabController _tabController;
  Position? _currentPosition;
  bool _isLoadingLocation = false;
  List<FamilyMemberModel> _familyMembers = [];
  StreamSubscription? _membersSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchCurrentLocation();
    _subscribeToMembers();
  }

  void _subscribeToMembers() {
    _membersSub = _dbService.streamFamilyMembers(widget.familyName).listen((members) {
      if (mounted) {
        setState(() => _familyMembers = members);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _membersSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      Position? pos;
      if (!kIsWeb) {
        try {
          pos = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }
      pos ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (mounted) {
        setState(() => _currentPosition = pos);
      }
    } catch (e) {
      debugPrint('[PlacesManager] Location fetch notice: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Safe Places & Geofencing',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              'Family: ${widget.familyName.isNotEmpty ? widget.familyName : "My Family"}',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.place_rounded, size: 20), text: 'Safe Places'),
            Tab(icon: Icon(Icons.history_rounded, size: 20), text: 'Place Activity'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPlacesListTab(),
          _buildActivityTimelineTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditPlaceModal(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Add Safe Place', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ===========================================================================
  // TAB 1: PLACES LIST
  // ===========================================================================
  Widget _buildPlacesListTab() {
    return StreamBuilder<List<GeofencePlaceModel>>(
      stream: _dbService.streamFamilyPlaces(widget.familyName),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final places = snapshot.data ?? [];

        if (places.isEmpty) {
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
                    child: const Icon(Icons.shield_outlined, size: 42, color: AppColors.primary),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'No Safe Places Configured',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create safe zones (like Home, School, or Office) to receive automatic alerts when family members arrive or leave.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _showAddEditPlaceModal(),
                    icon: const Icon(Icons.add_location_alt_rounded),
                    label: const Text('Add First Place'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          itemCount: places.length,
          itemBuilder: (context, index) {
            final place = places[index];
            return _buildPlaceCard(place);
          },
        );
      },
    );
  }

  Widget _buildPlaceCard(GeofencePlaceModel place) {
    String distanceText = '';
    if (_currentPosition != null && place.latitude != 0.0 && place.longitude != 0.0) {
      final distMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        place.latitude,
        place.longitude,
      );
      if (distMeters < 1000) {
        distanceText = '${distMeters.round()} m away';
      } else {
        distanceText = '${(distMeters / 1000).toStringAsFixed(1)} km away';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      shadowColor: Colors.black12,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Category Icon Badge
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: place.category.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(place.category.icon, color: place.category.color, size: 26),
                ),
                const SizedBox(width: 14),

                // Name & Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              'Radius: ${place.radiusMeters.round()}m',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: place.isForAllMembers ? const Color(0xFFEEF2FF) : const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: place.isForAllMembers ? const Color(0xFFC7D2FE) : const Color(0xFFA7F3D0)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  place.isForAllMembers ? Icons.groups_rounded : Icons.person_rounded,
                                  size: 11,
                                  color: place.isForAllMembers ? const Color(0xFF4F46E5) : const Color(0xFF059669),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  place.isForAllMembers ? 'All Family' : place.targetMemberName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: place.isForAllMembers ? const Color(0xFF4338CA) : const Color(0xFF047857),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (distanceText.isNotEmpty)
                            Text(
                              distanceText,
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Actions Menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
                  onSelected: (val) {
                    if (val == 'edit') {
                      _showAddEditPlaceModal(existingPlace: place);
                    } else if (val == 'delete') {
                      _confirmDeletePlace(place);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18, color: AppColors.primary),
                          SizedBox(width: 8),
                          Text('Edit Place'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Alert Toggles Indicators & Schedule
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildAlertBadge(
                  label: 'Arrival Alert',
                  icon: Icons.login_rounded,
                  isActive: place.notifyOnEntry,
                ),
                _buildAlertBadge(
                  label: 'Departure Alert',
                  icon: Icons.logout_rounded,
                  isActive: place.notifyOnExit,
                ),
                _buildAlertBadge(
                  label: place.formattedSchedule,
                  icon: Icons.schedule_rounded,
                  isActive: place.isScheduleActive,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertBadge({
    required String label,
    required IconData icon,
    required bool isActive,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFF0FDF4) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isActive ? const Color(0xFFBBF7D0) : Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isActive ? const Color(0xFF16A34A) : Colors.grey.shade500,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isActive ? const Color(0xFF15803D) : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 2: ACTIVITY TIMELINE
  // ===========================================================================
  Widget _buildActivityTimelineTab() {
    return StreamBuilder<List<PlaceEventModel>>(
      stream: _dbService.streamRecentPlaceEvents(widget.familyName),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final events = snapshot.data ?? [];

        if (events.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timeline_rounded, size: 54, color: Colors.grey.shade400),
                  const SizedBox(height: 14),
                  const Text(
                    'No Place Activity Yet',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Arrival and departure events will appear here automatically when family members enter or leave configured safe places.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: events.length,
          itemBuilder: (context, index) {
            final event = events[index];
            final timeStr = DateFormat('dd MMM, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(event.timestamp));
            final isArrival = event.isArrival;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isArrival ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isArrival ? Icons.login_rounded : Icons.logout_rounded,
                      color: isArrival ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                            children: [
                              TextSpan(text: event.memberName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: isArrival ? ' arrived at ' : ' left '),
                              TextSpan(text: event.placeName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          timeStr,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // ADD / EDIT PLACE MODAL
  // ===========================================================================
  void _showAddEditPlaceModal({GeofencePlaceModel? existingPlace}) {
    final isEditing = existingPlace != null;
    final nameCtrl = TextEditingController(text: existingPlace?.name ?? '');
    PlaceCategory selectedCategory = existingPlace?.category ?? PlaceCategory.home;
    double radius = existingPlace?.radiusMeters ?? 150.0;
    bool notifyEntry = existingPlace?.notifyOnEntry ?? true;
    bool notifyExit = existingPlace?.notifyOnExit ?? true;
    String targetMobile = existingPlace?.targetMemberMobile ?? '';
    String targetName = existingPlace?.targetMemberName ?? 'Everyone';

    bool isScheduleActive = existingPlace?.isScheduleActive ?? false;
    int startHour = existingPlace?.startHour ?? 8;
    int startMinute = existingPlace?.startMinute ?? 0;
    int endHour = existingPlace?.endHour ?? 18;
    int endMinute = existingPlace?.endMinute ?? 0;
    List<int> activeDays = List<int>.from(existingPlace?.activeDays ?? [1, 2, 3, 4, 5, 6, 7]);

    double lat = existingPlace?.latitude ?? widget.initialLat ?? _currentPosition?.latitude ?? 0.0;
    double lng = existingPlace?.longitude ?? widget.initialLng ?? _currentPosition?.longitude ?? 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          // Preset suggestions
          final presets = [
            {'name': 'Home', 'cat': PlaceCategory.home},
            {'name': 'School', 'cat': PlaceCategory.school},
            {'name': 'Office', 'cat': PlaceCategory.work},
            {'name': 'Gym', 'cat': PlaceCategory.gym},
            {'name': 'Safe Zone', 'cat': PlaceCategory.custom},
          ];

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header
                  Row(
                    children: [
                      Icon(
                        isEditing ? Icons.edit_location_alt_rounded : Icons.add_location_alt_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isEditing ? 'Edit Safe Place' : 'Add New Safe Place',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Quick Presets
                  const Text('Quick Presets:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: presets.map((p) {
                      final pName = p['name'] as String;
                      final pCat = p['cat'] as PlaceCategory;
                      final isSelected = selectedCategory == pCat && nameCtrl.text == pName;

                      return ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(pCat.icon, size: 14, color: isSelected ? Colors.white : pCat.color),
                            const SizedBox(width: 4),
                            Text(pName),
                          ],
                        ),
                        selected: isSelected,
                        selectedColor: pCat.color,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setModalState(() {
                              selectedCategory = pCat;
                              if (nameCtrl.text.isEmpty || presets.any((item) => item['name'] == nameCtrl.text)) {
                                nameCtrl.text = pName;
                              }
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Monitored Member / Assign To
                  const Text(
                    'Monitored Family Member:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.bgApp,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: targetMobile,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary),
                        items: [
                          const DropdownMenuItem<String>(
                            value: '',
                            child: Row(
                              children: [
                                Icon(Icons.groups_rounded, size: 20, color: AppColors.primary),
                                SizedBox(width: 10),
                                Text('👨‍👩‍👧‍👦 Everyone in Family (Shared)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                          ),
                          ..._familyMembers.map((m) {
                            return DropdownMenuItem<String>(
                              value: m.mobile,
                              child: Row(
                                children: [
                                  const Icon(Icons.person_pin_rounded, size: 20, color: Color(0xFF059669)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${m.name} ${m.isAdmin ? "(Admin)" : ""}'.trim(),
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          if (targetMobile.isNotEmpty && !_familyMembers.any((m) => m.mobile == targetMobile))
                            DropdownMenuItem<String>(
                              value: targetMobile,
                              child: Row(
                                children: [
                                  const Icon(Icons.person_pin_rounded, size: 20, color: Color(0xFF059669)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '$targetName (Assigned Member)',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        onChanged: (val) {
                          setModalState(() {
                            targetMobile = val ?? '';
                            if (targetMobile.isEmpty) {
                              targetName = 'Everyone';
                            } else {
                              final found = _familyMembers.firstWhere(
                                (m) => m.mobile == targetMobile,
                                orElse: () => FamilyMemberModel(name: targetName.isNotEmpty ? targetName : 'Member', mobile: targetMobile),
                              );
                              targetName = found.name;
                            }
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Name Field
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Place Name',
                      hintText: 'e.g. Home, St. Mary School, Office',
                      prefixIcon: Icon(selectedCategory.icon, color: selectedCategory.color),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Location Picker Button
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bgApp,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.my_location_rounded, size: 16, color: AppColors.primary),
                            const SizedBox(width: 6),
                            const Text(
                              'Place Coordinates:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _isLoadingLocation
                                  ? null
                                  : () async {
                                      setModalState(() => _isLoadingLocation = true);
                                      try {
                                        final pos = await Geolocator.getCurrentPosition(
                                          desiredAccuracy: LocationAccuracy.high,
                                        );
                                        setModalState(() {
                                          lat = pos.latitude;
                                          lng = pos.longitude;
                                          _isLoadingLocation = false;
                                        });
                                      } catch (e) {
                                        setModalState(() => _isLoadingLocation = false);
                                      }
                                    },
                              icon: _isLoadingLocation
                                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.gps_fixed_rounded, size: 14),
                              label: const Text('Use GPS', style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                lat == 0.0 && lng == 0.0
                                    ? 'No location set yet'
                                    : 'Lat: ${lat.toStringAsFixed(5)} • Lng: ${lng.toStringAsFixed(5)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: lat == 0.0 && lng == 0.0 ? Colors.red.shade400 : AppColors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final result = await Navigator.push<PlacePickerResult>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (ctx) => PlacePickerScreen(
                                      initialLat: lat != 0.0 ? lat : (_currentPosition?.latitude ?? 0.0),
                                      initialLng: lng != 0.0 ? lng : (_currentPosition?.longitude ?? 0.0),
                                      initialRadius: radius,
                                      category: selectedCategory,
                                      placeName: nameCtrl.text.trim(),
                                    ),
                                  ),
                                );
                                if (result != null) {
                                  setModalState(() {
                                    lat = result.latitude;
                                    lng = result.longitude;
                                    radius = result.radiusMeters;
                                  });
                                }
                              },
                              icon: const Icon(Icons.map_rounded, size: 15),
                              label: const Text('Pick on Map', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: selectedCategory.color,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: 1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Radius Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Safe Zone Radius:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${radius.round()} meters',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: radius,
                    min: 50.0,
                    max: 1000.0,
                    divisions: 19,
                    activeColor: selectedCategory.color,
                    label: '${radius.round()}m',
                    onChanged: (val) => setModalState(() => radius = val),
                  ),

                  // Notification Toggles
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Notify on Arrival', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Receive notification when family members arrive here', style: TextStyle(fontSize: 11)),
                    value: notifyEntry,
                    activeThumbColor: selectedCategory.color,
                    onChanged: (val) => setModalState(() => notifyEntry = val),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Notify on Departure', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Receive notification when family members leave here', style: TextStyle(fontSize: 11)),
                    value: notifyExit,
                    activeThumbColor: selectedCategory.color,
                    onChanged: (val) => setModalState(() => notifyExit = val),
                  ),
                  const SizedBox(height: 10),

                  // Schedule Configuration Toggle & Pickers
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bgApp,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isScheduleActive ? selectedCategory.color.withValues(alpha: 0.4) : AppColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Active Schedule / Time Window', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            isScheduleActive
                                ? 'Alerts only trigger during active days and hours'
                                : 'Alerts active 24/7 whenever crossed',
                            style: const TextStyle(fontSize: 11),
                          ),
                          value: isScheduleActive,
                          activeThumbColor: selectedCategory.color,
                          onChanged: (val) => setModalState(() => isScheduleActive = val),
                        ),

                        if (isScheduleActive) ...[
                          const SizedBox(height: 6),
                          const Text('Active Days:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              {'label': 'M', 'day': 1},
                              {'label': 'T', 'day': 2},
                              {'label': 'W', 'day': 3},
                              {'label': 'T', 'day': 4},
                              {'label': 'F', 'day': 5},
                              {'label': 'S', 'day': 6},
                              {'label': 'S', 'day': 7},
                            ].map((item) {
                              final day = item['day'] as int;
                              final label = item['label'] as String;
                              final isSelected = activeDays.contains(day);
                              return InkWell(
                                onTap: () {
                                  setModalState(() {
                                    if (isSelected) {
                                      if (activeDays.length > 1) activeDays.remove(day);
                                    } else {
                                      activeDays.add(day);
                                      activeDays.sort();
                                    }
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isSelected ? selectedCategory.color : Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: isSelected ? selectedCategory.color : Colors.grey.shade300),
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? Colors.white : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 10),

                          // Time Window Pickers (Start & End)
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final picked = await showTimePicker(
                                      context: modalCtx,
                                      initialTime: TimeOfDay(hour: startHour, minute: startMinute),
                                    );
                                    if (picked != null) {
                                      setModalState(() {
                                        startHour = picked.hour;
                                        startMinute = picked.minute;
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.access_time_rounded, size: 15),
                                  label: Text('From: ${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.textPrimary,
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final picked = await showTimePicker(
                                      context: modalCtx,
                                      initialTime: TimeOfDay(hour: endHour, minute: endMinute),
                                    );
                                    if (picked != null) {
                                      setModalState(() {
                                        endHour = picked.hour;
                                        endMinute = picked.minute;
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.access_time_filled_rounded, size: 15),
                                  label: Text('To: ${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.textPrimary,
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a place name')),
                          );
                          return;
                        }
                        if (lat == 0.0 && lng == 0.0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please set valid coordinates')),
                          );
                          return;
                        }

                        final placeToSave = GeofencePlaceModel(
                          id: existingPlace?.id ?? '',
                          familyName: widget.familyName,
                          name: name,
                          category: selectedCategory,
                          latitude: lat,
                          longitude: lng,
                          radiusMeters: radius,
                          notifyOnEntry: notifyEntry,
                          notifyOnExit: notifyExit,
                          targetMemberMobile: targetMobile,
                          targetMemberName: targetName,
                          createdBy: widget.userPhone,
                          isScheduleActive: isScheduleActive,
                          startHour: startHour,
                          startMinute: startMinute,
                          endHour: endHour,
                          endMinute: endMinute,
                          activeDays: activeDays,
                        );

                        final success = await _dbService.savePlace(placeToSave);
                        if (modalCtx.mounted) {
                          Navigator.pop(modalCtx);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: success ? AppColors.success : Colors.red,
                              content: Text(success ? 'Safe place saved successfully!' : 'Failed to save place.'),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedCategory.color,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        isEditing ? 'Save Changes' : 'Create Safe Place',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDeletePlace(GeofencePlaceModel place) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${place.name}"?'),
        content: const Text('Are you sure you want to delete this safe place? Geofence alerts for this place will be stopped.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await _dbService.deletePlace(widget.familyName, place.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: success ? AppColors.success : Colors.red,
                    content: Text(success ? 'Place deleted.' : 'Failed to delete place.'),
                  ),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
