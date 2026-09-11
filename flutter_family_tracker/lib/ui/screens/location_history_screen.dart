import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../../constants/app_colors.dart';
import '../../models/family_member_model.dart';
import '../../models/location_details_model.dart';
import '../../services/database_service.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../services/geocoding_service.dart';
import '../widgets/adaptive_map_view.dart';

enum HistoryTimeFilter {
  all,
  morning, // 06:00 - 12:00
  afternoon, // 12:00 - 18:00
  evening, // 18:00 - 24:00
  night, // 00:00 - 06:00
}

class LocationHistoryScreen extends StatefulWidget {
  final FamilyMemberModel member;

  const LocationHistoryScreen({super.key, required this.member});

  @override
  State<LocationHistoryScreen> createState() => _LocationHistoryScreenState();
}

class _LocationHistoryScreenState extends State<LocationHistoryScreen> {
  final DatabaseService _dbService = DatabaseService();
  final ScrollController _scrollController = ScrollController();
  DateTime _selectedDate = DateTime.now();
  List<LocationDetailsModel> _rawHistoryPoints = [];
  List<LocationDetailsModel> _displayedPoints = [];
  HistoryTimeFilter _selectedTimeFilter = HistoryTimeFilter.all;
  int? _selectedIndex;
  bool _isLoading = false;

  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _isLoading = true;
      _selectedIndex = null;
    });
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final points = await _dbService.getLocationHistory(widget.member.mobile, dateStr);

    if (mounted) {
      setState(() {
        _rawHistoryPoints = points;
        _applyTimeFilterAndRebuild();
        _isLoading = false;
      });
    }

    // Asynchronously resolve any addresses missing full details
    _resolveAddresses(points);
  }

  void _applyTimeFilterAndRebuild() {
    List<LocationDetailsModel> filtered;

    if (_selectedTimeFilter == HistoryTimeFilter.all) {
      filtered = List.from(_rawHistoryPoints);
    } else {
      filtered = _rawHistoryPoints.where((p) {
        if (p.timeStamp <= 0) return true;
        final hour = DateTime.fromMillisecondsSinceEpoch(p.timeStamp).hour;
        switch (_selectedTimeFilter) {
          case HistoryTimeFilter.morning:
            return hour >= 6 && hour < 12;
          case HistoryTimeFilter.afternoon:
            return hour >= 12 && hour < 18;
          case HistoryTimeFilter.evening:
            return hour >= 18 && hour < 24;
          case HistoryTimeFilter.night:
            return hour >= 0 && hour < 6;
          case HistoryTimeFilter.all:
            return true;
        }
      }).toList();
    }

    // 1. Sort latest update on top (Newest to Oldest)
    filtered.sort((a, b) => b.timeStamp.compareTo(a.timeStamp));
    _displayedPoints = filtered;

    // 2. Build Polyline based on chronological route (oldest to newest)
    final chronological = List<LocationDetailsModel>.from(filtered)
      ..sort((a, b) => a.timeStamp.compareTo(b.timeStamp));

    _polylines.clear();
    final polylineCoords = <LatLng>[];

    for (int i = 0; i < chronological.length; i++) {
      final p = chronological[i];
      if (p.latitude != 0.0 && p.longitude != 0.0) {
        polylineCoords.add(LatLng(p.latitude, p.longitude));
      }
    }

    if (polylineCoords.isNotEmpty) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('history_route'),
          points: polylineCoords,
          color: AppColors.primary,
          width: 5,
        ),
      );

      _fitMapToBounds(polylineCoords);
    }

    _buildMarkers();
  }

  void _buildMarkers() {
    _markers.clear();
    final formattedDate = DateFormat('MMM dd, yyyy').format(_selectedDate);

    for (int i = 0; i < _displayedPoints.length; i++) {
      final p = _displayedPoints[i];
      if (p.latitude != 0.0 && p.longitude != 0.0) {
        final pos = LatLng(p.latitude, p.longitude);
        final isSelected = _selectedIndex == i;
        final isLatest = i == 0; // Top item is latest
        final isStart = i == _displayedPoints.length - 1; // Bottom item is start

        if (isSelected || isLatest || isStart || _displayedPoints.length <= 15 || i % 3 == 0) {
          final timeStr = p.timeStamp > 0
              ? DateFormat('hh:mm:ss a').format(
                  DateTime.fromMillisecondsSinceEpoch(p.timeStamp),
                )
              : '';

          final markerId = MarkerId('point_$i');

          BitmapDescriptor icon;
          if (isSelected) {
            icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
          } else if (isLatest) {
            icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
          } else if (isStart) {
            icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
          } else {
            icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
          }

          final label = isLatest
              ? '🔴 Latest Location (#1)'
              : (isStart ? '🟢 Start Location' : 'Update #${_displayedPoints.length - i}');

          final addr = p.address.isNotEmpty
              ? p.address
              : 'Lat: ${p.latitude.toStringAsFixed(5)}, Lng: ${p.longitude.toStringAsFixed(5)}';

          _markers.add(
            Marker(
              markerId: markerId,
              position: pos,
              icon: icon,
              zIndexInt: isSelected ? 100 : (isLatest ? 20 : (isStart ? 15 : 5)),
              infoWindow: InfoWindow(
                title: isSelected ? '📍 Selected • $timeStr' : label,
                snippet: '📅 $formattedDate • 🕒 $timeStr\n📍 $addr\n⚡ Battery: ${p.batteryPercentage}%',
              ),
              onTap: () {
                _onMarkerTapped(i);
              },
            ),
          );
        }
      }
    }
  }

  void _onCardTapped(int index) {
    if (index >= _displayedPoints.length) return;
    final p = _displayedPoints[index];
    if (p.latitude == 0.0 && p.longitude == 0.0) return;

    setState(() {
      _selectedIndex = index;
      _buildMarkers();
    });

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(p.latitude, p.longitude),
          zoom: 17,
        ),
      ),
    );

    Future.delayed(const Duration(milliseconds: 350), () {
      _mapController?.showMarkerInfoWindow(MarkerId('point_$index'));
    });
  }

  void _onMarkerTapped(int index) {
    setState(() {
      _selectedIndex = index;
      _buildMarkers();
    });
    _scrollToCard(index);
  }

  void _scrollToCard(int index) {
    if (_scrollController.hasClients) {
      const itemHeight = 90.0;
      final targetOffset = (index * itemHeight).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _resolveAddresses(List<LocationDetailsModel> points) async {
    bool updated = false;
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.address.isEmpty || p.address.startsWith('Lat:')) {
        final resolved = await GeocodingService.getAddressFromCoordinates(
          p.latitude,
          p.longitude,
        );
        if (resolved.isNotEmpty && !resolved.startsWith('Lat:')) {
          p.address = resolved;
          updated = true;
        }
      }
    }
    if (updated && mounted) {
      setState(() {
        _applyTimeFilterAndRebuild();
      });
    }
  }

  void _fitMapToBounds(List<LatLng> coords) {
    if (_mapController == null || coords.isEmpty) return;

    double minLat = coords.first.latitude;
    double maxLat = coords.first.latitude;
    double minLng = coords.first.longitude;
    double maxLng = coords.first.longitude;

    for (var pos in coords) {
      if (pos.latitude < minLat) minLat = pos.latitude;
      if (pos.latitude > maxLat) maxLat = pos.latitude;
      if (pos.longitude < minLng) minLng = pos.longitude;
      if (pos.longitude > maxLng) maxLng = pos.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat - 0.005, minLng - 0.005),
      northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
    );

    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _fetchHistory();
    }
  }

  void _changeDateByDays(int days) {
    final newDate = _selectedDate.add(Duration(days: days));
    if (newDate.isAfter(DateTime.now())) return;
    setState(() => _selectedDate = newDate);
    _fetchHistory();
  }

  // Clear / Delete Location History Dialog
  Future<void> _showClearHistoryDialog() async {
    final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.delete_sweep_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text('Clear History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(
          'Choose which location history to delete for ${widget.member.name}:',
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          // Cancel
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),

          // Delete this date only
          OutlinedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _performClearHistory(dateStr: formattedDate);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Delete $formattedDate'),
          ),

          // Delete all history
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _performClearHistory(dateStr: null);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete All History'),
          ),
        ],
      ),
    );
  }

  Future<void> _performClearHistory({String? dateStr}) async {
    setState(() => _isLoading = true);
    try {
      await _dbService.clearLocationHistory(widget.member.mobile, date: dateStr);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dateStr != null
                  ? 'History for $dateStr cleared.'
                  : 'All location history cleared for ${widget.member.name}.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
      await _fetchHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear history: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('EEE, MMM dd, yyyy').format(_selectedDate);
    final initialPos = _markers.isNotEmpty
        ? _markers.first.position
        : const LatLng(17.3850, 78.4867);

    final isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.member.name} History'),
        actions: [
          // Clear / Delete History Button
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Clear History',
            onPressed: _showClearHistoryDialog,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded),
            tooltip: 'Select Date',
            onPressed: _selectDate,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _fetchHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          // Date Filter Banner with Quick Prev/Next Navigation
          Container(
            color: AppColors.bgSurface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, color: AppColors.primary),
                  onPressed: () => _changeDateByDays(-1),
                  tooltip: 'Previous Day',
                ),
                InkWell(
                  onTap: _selectDate,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.event_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: isToday ? AppColors.textMuted : AppColors.primary,
                  ),
                  onPressed: isToday ? null : () => _changeDateByDays(1),
                  tooltip: 'Next Day',
                ),
              ],
            ),
          ),

          // Map Preview
          Expanded(
            flex: 3,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : AdaptiveMapView(
                    initialLat: initialPos.latitude,
                    initialLng: initialPos.longitude,
                    initialZoom: 14,
                    points: _displayedPoints.asMap().entries.map((entry) {
                      final i = entry.key;
                      final p = entry.value;
                      final isLatest = i == 0;
                      final isStart = i == _displayedPoints.length - 1;
                      return AdaptiveMapPoint(
                        id: 'point_$i',
                        latitude: p.latitude,
                        longitude: p.longitude,
                        title: isLatest
                            ? '🔴 Latest (${p.timeStamp > 0 ? DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(p.timeStamp)) : ''})'
                            : (isStart
                                ? '🟢 Start (${p.timeStamp > 0 ? DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(p.timeStamp)) : ''})'
                                : 'Update #${_displayedPoints.length - i}'),
                        snippet: p.address,
                        pinColor: isLatest
                            ? AppColors.danger
                            : (isStart ? AppColors.success : AppColors.primary),
                      );
                    }).toList(),
                    polylines: [
                      AdaptivePolyline(
                        id: 'history_route',
                        points: _displayedPoints
                            .where((p) => p.latitude != 0.0 && p.longitude != 0.0)
                            .map((p) => ll.LatLng(p.latitude, p.longitude))
                            .toList(),
                        color: AppColors.primary,
                        strokeWidth: 4,
                      ),
                    ],
                    googleMarkers: _markers,
                    googlePolylines: _polylines,
                    onGoogleMapCreated: (ctrl) {
                      _mapController = ctrl;
                      if (_polylines.isNotEmpty) {
                        final coords = _polylines.first.points;
                        _fitMapToBounds(coords);
                      }
                    },
                  ),
          ),

          // Timeline Section with Time Filter Chips & Latest Updates on Top
          Expanded(
            flex: 3,
            child: Container(
              color: AppColors.bgApp,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Header with Total Points & Time Span
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Updates (${_displayedPoints.length})',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (_displayedPoints.isNotEmpty)
                        Text(
                          'Latest: ${_displayedPoints.first.timeStamp > 0 ? DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(_displayedPoints.first.timeStamp)) : ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 2. Time Filter Chips Row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All (${_rawHistoryPoints.length})', HistoryTimeFilter.all),
                        const SizedBox(width: 6),
                        _buildFilterChip('🌅 Morning (6AM-12PM)', HistoryTimeFilter.morning),
                        const SizedBox(width: 6),
                        _buildFilterChip('☀️ Afternoon (12PM-6PM)', HistoryTimeFilter.afternoon),
                        const SizedBox(width: 6),
                        _buildFilterChip('🌆 Evening (6PM-12AM)', HistoryTimeFilter.evening),
                        const SizedBox(width: 6),
                        _buildFilterChip('🌙 Night (12AM-6AM)', HistoryTimeFilter.night),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 3. Timeline Cards List (Newest on Top)
                  Expanded(
                    child: _displayedPoints.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.location_off_rounded,
                                  size: 36,
                                  color: AppColors.textMuted.withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'No recorded points in this time range.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            itemCount: _displayedPoints.length,
                            itemBuilder: (context, index) {
                              final p = _displayedPoints[index];
                              final timeStr = p.timeStamp > 0
                                  ? DateFormat('hh:mm:ss a').format(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        p.timeStamp,
                                      ),
                                    )
                                  : 'Update ${index + 1}';

                              final isLatest = index == 0;
                              final isStart = index == _displayedPoints.length - 1;
                              final isSelected = _selectedIndex == index;

                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary.withValues(alpha: 0.08)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : (isLatest
                                            ? AppColors.danger.withValues(alpha: 0.5)
                                            : AppColors.cardBorder),
                                    width: isSelected ? 2.0 : 1.0,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: AppColors.primary.withValues(alpha: 0.25),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ]
                                      : [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.04),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: isSelected
                                        ? const Color(0xFFF59E0B) // Amber highlight
                                        : (isLatest
                                            ? AppColors.danger
                                            : (isStart
                                                ? AppColors.success
                                                : AppColors.primaryLight)),
                                    child: isSelected
                                        ? const Icon(
                                            Icons.location_on_rounded,
                                            color: Colors.white,
                                            size: 20,
                                          )
                                        : (isLatest
                                            ? const Icon(
                                                Icons.my_location_rounded,
                                                color: Colors.white,
                                                size: 18,
                                              )
                                            : Text(
                                                '${_displayedPoints.length - index}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              )),
                                  ),
                                  title: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Status Badge & Lat/Lng Coordinates
                                      Row(
                                        children: [
                                          if (isLatest) ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 1,
                                              ),
                                              margin: const EdgeInsets.only(right: 6),
                                              decoration: BoxDecoration(
                                                color: AppColors.dangerBg,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'LATEST',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.danger,
                                                ),
                                              ),
                                            ),
                                          ] else if (isStart) ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 1,
                                              ),
                                              margin: const EdgeInsets.only(right: 6),
                                              decoration: BoxDecoration(
                                                color: AppColors.successBg,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'START',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.success,
                                                ),
                                              ),
                                            ),
                                          ],
                                          const Icon(
                                            Icons.gps_fixed_rounded,
                                            size: 11,
                                            color: AppColors.accent,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'Lat: ${p.latitude.toStringAsFixed(5)}, Lng: ${p.longitude.toStringAsFixed(5)}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontFamily: 'monospace',
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.w600,
                                                color: isSelected
                                                    ? AppColors.primary
                                                    : AppColors.textSecondary,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),

                                      // Street Address below Lat and Lng
                                      Text(
                                        p.address.isNotEmpty
                                            ? p.address
                                            : 'Fetching street address...',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: AppColors.textPrimary,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '🕒 $timeStr • ⚡ ${p.batteryPercentage}%',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textMuted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  trailing: isSelected
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Text(
                                            'ON MAP',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                      : null,
                                  onTap: () => _onCardTapped(index),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, HistoryTimeFilter filter) {
    final isSelected = _selectedTimeFilter == filter;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTimeFilter = filter;
          _selectedIndex = null;
          _applyTimeFilterAndRebuild();
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.cardBorder,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
