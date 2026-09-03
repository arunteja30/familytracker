import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../../constants/app_colors.dart';
import '../../models/family_member_model.dart';
import '../../models/location_details_model.dart';
import '../../services/database_service.dart';

class LocationHistoryScreen extends StatefulWidget {
  final FamilyMemberModel member;

  const LocationHistoryScreen({super.key, required this.member});

  @override
  State<LocationHistoryScreen> createState() => _LocationHistoryScreenState();
}

class _LocationHistoryScreenState extends State<LocationHistoryScreen> {
  final DatabaseService _dbService = DatabaseService();
  DateTime _selectedDate = DateTime.now();
  List<LocationDetailsModel> _historyPoints = [];
  bool _isLoading = false;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final points = await _dbService.getLocationHistory(widget.member.mobile, dateStr);

    _markers.clear();
    _polylines.clear();

    final polylineCoords = <LatLng>[];

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.latitude != 0.0 && p.longitude != 0.0) {
        final pos = LatLng(p.latitude, p.longitude);
        polylineCoords.add(pos);

        // Marker for start, end and key points
        if (i == 0 || i == points.length - 1) {
          final timeStr = p.timeStamp > 0
              ? DateFormat('hh:mm a').format(
                  DateTime.fromMillisecondsSinceEpoch(p.timeStamp),
                )
              : '';
          _markers.add(
            Marker(
              markerId: MarkerId('point_$i'),
              position: pos,
              infoWindow: InfoWindow(
                title: i == 0 ? 'Start Location ($timeStr)' : 'Latest Location ($timeStr)',
                snippet: p.address,
              ),
            ),
          );
        }
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
    }

    setState(() {
      _historyPoints = points;
      _isLoading = false;
    });
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

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('MMM dd, yyyy').format(_selectedDate);
    final initialPos = _markers.isNotEmpty
        ? _markers.first.position
        : const LatLng(17.3850, 78.4867);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.member.name} History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: _selectDate,
          ),
        ],
      ),
      body: Column(
        children: [
          // Date Filter Banner
          Container(
            color: AppColors.bgSurface,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
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
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _selectDate,
                  child: const Text('Change Date'),
                ),
              ],
            ),
          ),

          // Map Preview
          Expanded(
            flex: 3,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: initialPos,
                      zoom: 14,
                    ),
                    markers: _markers,
                    polylines: _polylines,
                  ),
          ),

          // Timeline Section
          Expanded(
            flex: 2,
            child: Container(
              color: AppColors.bgApp,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recorded Points (${_historyPoints.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _historyPoints.isEmpty
                        ? const Center(
                            child: Text(
                              'No location points recorded on this date.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _historyPoints.length,
                            itemBuilder: (context, index) {
                              final p = _historyPoints[index];
                              final timeStr = p.timeStamp > 0
                                  ? DateFormat('hh:mm a').format(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        p.timeStamp,
                                      ),
                                    )
                                  : 'Point $index';

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    radius: 16,
                                    backgroundColor: AppColors.primaryLight,
                                    child: Icon(
                                      Icons.navigation_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                  title: Text(
                                    p.address.isNotEmpty
                                        ? p.address
                                        : 'Lat: ${p.latitude}, Lon: ${p.longitude}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '$timeStr • Battery: ${p.batteryPercentage}%',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
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
}
